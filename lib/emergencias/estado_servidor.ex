defmodule Emergencias.EstadoServidor do
  @moduledoc "GenServer coordinador: autoriza, serializa y persiste las mutaciones."
  use GenServer

  alias Emergencias.{
    Albergue,
    Albergues,
    Mensajes,
    AsignacionRecurso,
    Estado,
    Necesidad,
    Necesidades,
    MovimientoRecurso,
    Persistencia,
    Personas,
    Recurso,
    Recursos,
    Sesiones,
    Usuarios,
    Zonas
  }

  @zonas_estados [:baja, :media, :alta, :critica]
  @necesidades_estados [:pendiente, :asignada, :en_atencion, :atendida, :cancelada]

  @doc "Inicia el coordinador y recupera el snapshot JSON."
  def start_link(opts \\ []) do
    process_opts = opts |> Keyword.take([:name]) |> Keyword.put_new(:name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, process_opts)
  end

  @impl true
  def init(opts) do
    path = Keyword.get(opts, :path, Persistencia.ruta())

    with {:ok, estado} <- Persistencia.cargar(path),
         {:ok, estado, persistir?} <- provisionar_administrador(estado) do
      if persistir? do
        case Persistencia.guardar(estado, path) do
          :ok -> {:ok, %{estado: estado, ruta: path}}
          {:error, _razon} -> {:stop, :error_persistencia}
        end
      else
        {:ok, %{estado: estado, ruta: path}}
      end
    else
      {:error, _razon} -> {:stop, :error_persistencia}
    end
  end

  @impl true
  def handle_call(:ping, _from, coordinador), do: {:reply, :pong, coordinador}

  @impl true
  def handle_call(:obtener_estado, _from, %{estado: estado} = coordinador),
    do: {:reply, {:ok, estado}, coordinador}

  @impl true
  def handle_call({:conectar, attrs}, _from, %{estado: estado} = coordinador) do
    case Sesiones.conectar(estado, attrs) do
      {:ok, %{estado: nuevo_estado} = resultado} ->
        respuesta = Map.drop(resultado, [:estado])

        if estado.usuarios_por_username == nuevo_estado.usuarios_por_username do
          {:reply, {:ok, respuesta}, %{coordinador | estado: nuevo_estado}}
        else
          nuevo_estado =
            registrar_actividad(
              nuevo_estado,
              respuesta.usuario.username,
              :registrar_usuario,
              respuesta.usuario.username
            )

          guardar_y_confirmar(coordinador, nuevo_estado, respuesta)
        end

      {:error, motivo} ->
        {:reply, {:error, motivo}, coordinador}
    end
  end

  @impl true
  def handle_call({:desconectar, session_id}, _from, %{estado: estado} = coordinador) do
    case Sesiones.desconectar(estado, session_id) do
      {:ok, nuevo_estado} -> {:reply, :ok, %{coordinador | estado: nuevo_estado}}
      {:error, motivo} -> {:reply, {:error, motivo}, coordinador}
    end
  end

  @impl true
  def handle_call({:ejecutar, session_id, comando}, _from, coordinador) do
    with {:ok, actor} <- Sesiones.usuario_de_sesion(coordinador.estado, session_id),
         {:ok, nuevo_estado, resultado} <-
           ejecutar_comando(coordinador.estado, session_id, actor, comando) do
      guardar_y_confirmar(coordinador, nuevo_estado, resultado)
    else
      {:error, motivo} -> {:reply, {:error, motivo}, coordinador}
    end
  end

  @impl true
  def handle_call({:consultar, session_id, consulta}, _from, coordinador) do
    with {:ok, actor} <- Sesiones.usuario_de_sesion(coordinador.estado, session_id),
         {:ok, resultado} <-
           consultar_estado(coordinador.estado, session_id, actor, consulta) do
      {:reply, {:ok, resultado}, coordinador}
    else
      {:error, motivo} -> {:reply, {:error, motivo}, coordinador}
    end
  end

  @impl true
  def handle_call(_solicitud, _from, coordinador),
    do: {:reply, {:error, :comando_no_reconocido}, coordinador}

  defp ejecutar_comando(estado, session_id, actor, {:registrar_necesidad, attrs})
       when is_map(attrs) do
    zona_codigo = valor(attrs, :zona_codigo) |> normalizar_texto()

    with :ok <- autorizar_reporte(estado, session_id, actor, zona_codigo),
         id <- nuevo_id("N", estado.necesidades_por_id),
         attrs <- attrs |> Map.put(:id, id) |> Map.put(:responsable_id, actor.username),
         {:ok, necesidades} <-
           Necesidades.registrar(estado.necesidades_por_id, estado.zonas_por_codigo, attrs),
         {:ok, necesidad} <- Map.fetch(necesidades, id) do
      nuevo_estado = %{estado | necesidades_por_id: necesidades}
      nuevo_estado = registrar_actividad(nuevo_estado, actor.username, :registrar_necesidad, id)
      {:ok, nuevo_estado, necesidad}
    end
  end

  defp ejecutar_comando(estado, session_id, actor, {:registrar_recurso, attrs})
       when is_map(attrs) do
    zona_codigo = valor(attrs, :zona_codigo) |> normalizar_texto()

    with :ok <- autorizar_zona(estado, session_id, :asignar_recursos, zona_codigo),
         {:ok, recursos} <-
           Recursos.registrar(estado.recursos_por_codigo, estado.zonas_por_codigo, attrs),
         codigo <- valor(attrs, :codigo) |> normalizar_texto(),
         {:ok, recurso} <- Map.fetch(recursos, codigo),
         fecha <- ahora(),
         movimiento <-
           crear_movimiento(
             nuevo_id("M", estado.movimientos_por_id),
             codigo,
             "registro",
             recurso.ubicacion,
             recurso.cantidad_disponible,
             fecha,
             actor.username
           ),
         movimientos <- Map.put(estado.movimientos_por_id, movimiento.id, movimiento) do
      nuevo_estado = %{estado | recursos_por_codigo: recursos, movimientos_por_id: movimientos}
      nuevo_estado = registrar_actividad(nuevo_estado, actor.username, :registrar_recurso, codigo)
      {:ok, nuevo_estado, recurso}
    end
  end

  defp ejecutar_comando(estado, session_id, actor, {:ingresar_recurso, recurso_codigo, cantidad}) do
    with {:ok, %Recurso{} = recurso} <- Map.fetch(estado.recursos_por_codigo, recurso_codigo),
         :ok <- autorizar_zona(estado, session_id, :asignar_recursos, recurso.zona_codigo),
         {:ok, cantidad} <- cantidad_positiva(cantidad),
         {:ok, recursos} <-
           Recursos.ingresar(estado.recursos_por_codigo, recurso_codigo, cantidad),
         fecha <- ahora(),
         movimiento <-
           crear_movimiento(
             nuevo_id("M", estado.movimientos_por_id),
             recurso_codigo,
             "ingreso",
             recurso.ubicacion,
             cantidad,
             fecha,
             actor.username
           ) do
      nuevo_estado = %{
        estado
        | recursos_por_codigo: recursos,
          movimientos_por_id: Map.put(estado.movimientos_por_id, movimiento.id, movimiento)
      }

      nuevo_estado =
        registrar_actividad(nuevo_estado, actor.username, :ingresar_recurso, recurso_codigo)

      {:ok, nuevo_estado,
       %{recurso: Map.fetch!(recursos, recurso_codigo), movimiento: movimiento}}
    else
      :error -> {:error, :no_encontrado}
      {:error, motivo} -> {:error, motivo}
    end
  end

  defp ejecutar_comando(
         estado,
         session_id,
         actor,
         {:asignar_recurso, necesidad_id, recurso_codigo, cantidad}
       ) do
    with {:ok, %Necesidad{} = necesidad} <- Map.fetch(estado.necesidades_por_id, necesidad_id),
         :ok <- autorizar_zona(estado, session_id, :asignar_recursos, necesidad.zona_codigo),
         {:ok, %Recurso{} = recurso} <- Map.fetch(estado.recursos_por_codigo, recurso_codigo),
         :ok <- validar_asignacion(necesidad, recurso, estado.asignaciones_por_id, cantidad),
         {:ok, recursos} <-
           Recursos.descontar(estado.recursos_por_codigo, recurso_codigo, cantidad),
         {:ok, necesidades} <- asignar_necesidad(estado.necesidades_por_id, necesidad),
         fecha <- ahora(),
         asignacion <-
           %AsignacionRecurso{
             id: nuevo_id("A", estado.asignaciones_por_id),
             necesidad_id: necesidad_id,
             recurso_codigo: recurso_codigo,
             cantidad: normalizar_cantidad(cantidad),
             estado: :asignada,
             asignado_por: actor.username,
             fecha: fecha
           },
         movimiento <-
           crear_movimiento(
             nuevo_id("M", estado.movimientos_por_id),
             recurso_codigo,
             recurso.ubicacion,
             "necesidad:#{necesidad_id}",
             asignacion.cantidad,
             fecha,
             actor.username
           ) do
      nuevo_estado = %{
        estado
        | necesidades_por_id: necesidades,
          recursos_por_codigo: recursos,
          asignaciones_por_id: Map.put(estado.asignaciones_por_id, asignacion.id, asignacion),
          movimientos_por_id: Map.put(estado.movimientos_por_id, movimiento.id, movimiento)
      }

      nuevo_estado =
        registrar_actividad(nuevo_estado, actor.username, :asignar_recurso, asignacion.id)

      {:ok, nuevo_estado, asignacion}
    else
      :error -> {:error, :no_encontrado}
      {:error, motivo} -> {:error, motivo}
    end
  end

  defp ejecutar_comando(
         estado,
         session_id,
         actor,
         {:transferir_recurso, recurso_codigo, origen, destino, cantidad}
       ) do
    with {:ok, %Recurso{} = recurso} <- Map.fetch(estado.recursos_por_codigo, recurso_codigo),
         :ok <- autorizar_zona(estado, session_id, :transferir_recursos, recurso.zona_codigo),
         codigo_destino <- codigo_transferencia(estado.recursos_por_codigo, recurso, cantidad),
         {:ok, recursos, transferido} <-
           Recursos.transferir(
             estado.recursos_por_codigo,
             recurso_codigo,
             origen,
             destino,
             cantidad,
             codigo_destino
           ),
         fecha <- ahora(),
         movimiento <-
           crear_movimiento(
             nuevo_id("M", estado.movimientos_por_id),
             transferido.codigo,
             origen,
             destino,
             normalizar_cantidad(cantidad),
             fecha,
             actor.username
           ) do
      nuevo_estado = %{
        estado
        | recursos_por_codigo: recursos,
          movimientos_por_id: Map.put(estado.movimientos_por_id, movimiento.id, movimiento)
      }

      nuevo_estado =
        registrar_actividad(nuevo_estado, actor.username, :transferir_recurso, movimiento.id)

      {:ok, nuevo_estado, %{recurso: transferido, movimiento: movimiento}}
    else
      :error -> {:error, :no_encontrado}
      {:error, motivo} -> {:error, motivo}
    end
  end

  defp ejecutar_comando(
         estado,
         session_id,
         actor,
         {:cambiar_estado_necesidad, necesidad_id, nuevo_estado}
       ) do
    with {:ok, %Necesidad{} = necesidad} <- Map.fetch(estado.necesidades_por_id, necesidad_id),
         :ok <- autorizar_zona(estado, session_id, :asignar_recursos, necesidad.zona_codigo),
         :ok <- validar_cierre(necesidad, nuevo_estado, estado.asignaciones_por_id),
         {:ok, necesidades} <-
           Necesidades.cambiar_estado(estado.necesidades_por_id, necesidad_id, nuevo_estado),
         {:ok, estado_dominio} <-
           actualizar_asignaciones(
             estado,
             necesidad_id,
             enum(nuevo_estado, @necesidades_estados),
             actor.username
           ),
         actualizado <- %{estado_dominio | necesidades_por_id: necesidades},
         actualizado <-
           registrar_actividad(
             actualizado,
             actor.username,
             :cambiar_estado_necesidad,
             necesidad_id
           ) do
      {:ok, actualizado, Map.fetch!(necesidades, necesidad_id)}
    else
      :error -> {:error, :no_encontrado}
      {:error, motivo} -> {:error, motivo}
    end
  end

  defp ejecutar_comando(estado, session_id, actor, {:registrar_zona, attrs})
       when is_map(attrs) do
    with :ok <- autorizar(estado, session_id, :crear_zonas),
         {:ok, zona} <- construir_zona(attrs),
         {:ok, zonas} <- Zonas.registrar(estado.zonas_por_codigo, zona) do
      actualizado = %{estado | zonas_por_codigo: zonas}
      actualizado = registrar_actividad(actualizado, actor.username, :registrar_zona, zona.codigo)
      {:ok, actualizado, zona}
    end
  end

  defp ejecutar_comando(estado, session_id, actor, {:registrar_sector, zona_codigo, attrs})
       when is_map(attrs) do
    with :ok <- autorizar(estado, session_id, :crear_zonas),
         {:ok, sector} <- construir_sector(attrs),
         {:ok, zonas} <- Zonas.agregar_sector(estado.zonas_por_codigo, zona_codigo, sector) do
      actualizado = %{estado | zonas_por_codigo: zonas}

      actualizado =
        registrar_actividad(actualizado, actor.username, :registrar_sector, sector.codigo)

      {:ok, actualizado, sector}
    end
  end

  defp ejecutar_comando(
         estado,
         session_id,
         actor,
         {:registrar_punto_atencion, zona_codigo, sector_codigo, attrs}
       )
       when is_map(attrs) do
    with :ok <- autorizar(estado, session_id, :crear_zonas),
         {:ok, punto} <- construir_punto(attrs),
         {:ok, zonas} <-
           Zonas.agregar_punto(estado.zonas_por_codigo, zona_codigo, sector_codigo, punto) do
      actualizado = %{estado | zonas_por_codigo: zonas}

      actualizado =
        registrar_actividad(actualizado, actor.username, :registrar_punto_atencion, punto.codigo)

      {:ok, actualizado, punto}
    end
  end

  defp ejecutar_comando(
         estado,
         session_id,
         actor,
         {:cambiar_estado_punto_atencion, zona_codigo, sector_codigo, punto_codigo, punto_estado}
       ) do
    with :ok <- autorizar(estado, session_id, :crear_zonas),
         punto_estado when not is_nil(punto_estado) <-
           enum(punto_estado, [:activo, :inactivo, :saturado]),
         {:ok, zonas} <-
           Zonas.cambiar_estado_punto(
             estado.zonas_por_codigo,
             zona_codigo,
             sector_codigo,
             punto_codigo,
             punto_estado
           ) do
      actualizado = %{estado | zonas_por_codigo: zonas}

      actualizado =
        registrar_actividad(
          actualizado,
          actor.username,
          :cambiar_estado_punto_atencion,
          punto_codigo
        )

      {:ok, actualizado, :ok}
    else
      nil -> {:error, :estado_invalido}
      {:error, motivo} -> {:error, motivo}
    end
  end

  defp ejecutar_comando(estado, session_id, actor, {:asignar_rol, username, rol}) do
    with :ok <- autorizar(estado, session_id, :gestionar_usuarios),
         {:ok, usuarios} <-
           Usuarios.asignar_rol_autorizado(
             estado.usuarios_por_username,
             actor.username,
             username,
             enum(rol, Usuarios.roles())
           ) do
      actualizado = %{estado | usuarios_por_username: usuarios}
      actualizado = registrar_actividad(actualizado, actor.username, :asignar_rol, username)
      {:ok, actualizado, Map.fetch!(usuarios, username) |> Usuarios.usuario_publico()}
    end
  end

  defp ejecutar_comando(estado, session_id, actor, {:registrar_albergue, attrs})
       when is_map(attrs) do
    zona_codigo = valor(attrs, :zona_codigo) |> normalizar_texto()

    with :ok <- autorizar_zona(estado, session_id, :gestionar_albergue, zona_codigo),
         {:ok, albergues} <-
           Albergues.registrar(estado.albergues_por_codigo, estado.zonas_por_codigo, attrs),
         codigo <- valor(attrs, :codigo) |> normalizar_texto(),
         albergue <- Map.fetch!(albergues, codigo) do
      actualizado = %{estado | albergues_por_codigo: albergues}
      actualizado = registrar_actividad(actualizado, actor.username, :registrar_albergue, codigo)
      {:ok, actualizado, albergue}
    end
  end

  defp ejecutar_comando(
         estado,
         session_id,
         actor,
         {:registrar_entrada_albergue, albergue_codigo, persona_id}
       ) do
    with codigo when is_binary(codigo) <- normalizar_texto(albergue_codigo),
         id_persona when is_binary(id_persona) <- normalizar_texto(persona_id),
         %Albergue{} = albergue <- Map.get(estado.albergues_por_codigo, codigo),
         :ok <- autorizar_zona(estado, session_id, :gestionar_albergue, albergue.zona_codigo),
         estancia_id <- nuevo_id("E", estado.estancias_por_id),
         fecha_ingreso <- ahora(),
         {:ok, estancias} <-
           Albergues.registrar_ingreso(
             estado.albergues_por_codigo,
             estado.estancias_por_id,
             estado.personas_por_id,
             codigo,
             id_persona,
             estancia_id,
             fecha_ingreso
           ) do
      actualizado = %{estado | estancias_por_id: estancias}

      actualizado =
        registrar_actividad(actualizado, actor.username, :registrar_entrada_albergue, estancia_id)

      {:ok, actualizado, Map.fetch!(estancias, estancia_id)}
    else
      nil -> {:error, :no_encontrado}
      {:error, motivo} -> {:error, motivo}
    end
  end

  defp ejecutar_comando(
         estado,
         session_id,
         actor,
         {:registrar_salida_albergue, albergue_codigo, persona_id}
       ) do
    with codigo when is_binary(codigo) <- normalizar_texto(albergue_codigo),
         id_persona when is_binary(id_persona) <- normalizar_texto(persona_id),
         %Albergue{} = albergue <- Map.get(estado.albergues_por_codigo, codigo),
         :ok <- autorizar_zona(estado, session_id, :gestionar_albergue, albergue.zona_codigo),
         estancia_activa <-
           Enum.find_value(estado.estancias_por_id, fn {_id, estancia} ->
             if estancia.albergue_codigo == codigo and estancia.persona_id == id_persona and
                  is_nil(estancia.fecha_salida),
                do: estancia
           end),
         true <- not is_nil(estancia_activa),
         fecha_salida <- ahora(),
         {:ok, estancias} <-
           Albergues.registrar_salida(
             estado.estancias_por_id,
             codigo,
             id_persona,
             fecha_salida
           ),
         estancia <- Map.fetch!(estancias, estancia_activa.id) do
      actualizado = %{estado | estancias_por_id: estancias}

      actualizado =
        registrar_actividad(actualizado, actor.username, :registrar_salida_albergue, estancia.id)

      {:ok, actualizado, estancia}
    else
      false -> {:error, :estancia_activa_no_encontrada}
      nil -> {:error, :no_encontrado}
      {:error, motivo} -> {:error, motivo}
    end
  end

  defp ejecutar_comando(estado, session_id, actor, {:reportar_persona, attrs})
       when is_map(attrs) do
    zona = valor(attrs, :zona_codigo) |> normalizar_texto()

    with :ok <- autorizar_reporte(estado, session_id, actor, zona),
         id <- nuevo_id("P", estado.personas_por_id),
         {:ok, personas} <-
           Personas.registrar(
             estado.personas_por_id,
             estado.zonas_por_codigo,
             Map.put(attrs, :id, id)
           ) do
      actualizado = %{estado | personas_por_id: personas}
      actualizado = registrar_actividad(actualizado, actor.username, :reportar_persona, id)
      {:ok, actualizado, Map.fetch!(personas, id)}
    end
  end

  defp ejecutar_comando(estado, session_id, actor, {:cambiar_estado_persona, id, nuevo_estado}) do
    with {:ok, persona} <- persona_visible(estado, session_id, actor, id),
         :ok <- autorizar_cambio_persona(estado, session_id, actor, persona),
         contexto <- %{
           id: nuevo_id("CP", Map.new(estado.historial_personas, &{&1.id, &1})),
           fecha: ahora(),
           usuario_id: actor.username
         },
         {:ok, resultado} <-
           Personas.cambiar_estado(
             estado.personas_por_id,
             estado.historial_personas,
             id,
             nuevo_estado,
             contexto
           ) do
      actualizado = %{
        estado
        | personas_por_id: resultado.personas,
          historial_personas: resultado.historial
      }

      actualizado = registrar_actividad(actualizado, actor.username, :cambiar_estado_persona, id)
      {:ok, actualizado, Map.fetch!(resultado.personas, id)}
    end
  end

  defp ejecutar_comando(estado, session_id, actor, {:enviar_mensaje_familiar, persona_id, attrs})
       when is_map(attrs) do
    with {:ok, persona} <- persona_visible(estado, session_id, actor, persona_id),
         :ok <- autorizar_reporte(estado, session_id, actor, persona.zona_codigo),
         id <- nuevo_id("MF", estado.mensajes_por_id),
         attrs <- attrs |> Map.put(:id, id) |> Map.put(:fecha, ahora()),
         {:ok, mensajes} <-
           Mensajes.crear(estado.mensajes_por_id, estado.personas_por_id, persona_id, attrs) do
      actualizado = %{estado | mensajes_por_id: mensajes}
      actualizado = registrar_actividad(actualizado, actor.username, :enviar_mensaje_familiar, id)
      {:ok, actualizado, Map.fetch!(mensajes, id)}
    end
  end

  defp ejecutar_comando(estado, session_id, actor, {:marcar_mensaje_entregado, id}) do
    with {:ok, mensaje} <- Mensajes.obtener(estado.mensajes_por_id, id),
         {:ok, persona} <- persona_visible(estado, session_id, actor, mensaje.persona_id),
         :ok <- autorizar_zona(estado, session_id, :atender_mensaje, persona.zona_codigo),
         {:ok, mensajes} <- Mensajes.marcar_entregado(estado.mensajes_por_id, id) do
      actualizado = %{estado | mensajes_por_id: mensajes}

      actualizado =
        registrar_actividad(actualizado, actor.username, :marcar_mensaje_entregado, id)

      {:ok, actualizado, Map.fetch!(mensajes, id)}
    end
  end

  defp ejecutar_comando(_estado, _session_id, _actor, comando)
       when is_tuple(comando) and tuple_size(comando) > 0 and
              elem(comando, 0) in [
                :reportar_persona,
                :enviar_mensaje_familiar,
                :reportar_mascota,
                :confirmar_coincidencia_mascota
              ],
       do: {:error, :dominio_no_disponible}

  defp ejecutar_comando(_estado, _session_id, _actor, _comando),
    do: {:error, :comando_no_reconocido}

  defp consultar_estado(estado, session_id, actor, {:necesidades, filtros})
       when is_map(filtros) do
    with {:ok, filtros} <- filtros_por_zona(estado, session_id, actor, filtros),
         {:ok, necesidades} <-
           Necesidades.listar(estado.necesidades_por_id, filtros, estado.actividad) do
      {:ok, necesidades}
    end
  end

  defp consultar_estado(estado, session_id, actor, {:recursos, filtros})
       when is_map(filtros) do
    with {:ok, filtros} <- filtros_por_zona(estado, session_id, actor, filtros),
         {:ok, recursos} <- Recursos.listar(estado.recursos_por_codigo, filtros) do
      {:ok, recursos}
    end
  end

  defp consultar_estado(estado, session_id, actor, {:movimientos, filtros})
       when is_map(filtros) do
    with {:ok, filtros} <- filtros_por_zona(estado, session_id, actor, filtros),
         {:ok, movimientos} <-
           Recursos.movimientos(
             estado.movimientos_por_id,
             estado.recursos_por_codigo,
             filtros
           ) do
      {:ok, movimientos}
    end
  end

  defp consultar_estado(estado, session_id, actor, :necesidades_pendientes),
    do: consultar_estado(estado, session_id, actor, {:necesidades, %{estado: :pendiente}})

  defp consultar_estado(estado, session_id, actor, :recursos_criticos),
    do: consultar_estado(estado, session_id, actor, {:recursos_criticos, %{}})

  defp consultar_estado(estado, session_id, actor, {:recursos_criticos, filtros})
       when is_map(filtros) do
    with {:ok, filtros} <- filtros_por_zona(estado, session_id, actor, filtros),
         {:ok, recursos} <- Recursos.listar(estado.recursos_por_codigo, filtros, true) do
      {:ok, recursos}
    end
  end

  defp consultar_estado(estado, session_id, actor, :resumen) do
    with {:ok, filtros} <- filtros_por_zona(estado, session_id, actor, %{}),
         {:ok, necesidades} <-
           Necesidades.listar(estado.necesidades_por_id, filtros, estado.actividad),
         {:ok, recursos} <- Recursos.listar(estado.recursos_por_codigo, filtros) do
      {:ok, resumen(estado, necesidades, recursos, filtros.zona_codigo)}
    end
  end

  defp consultar_estado(estado, session_id, actor, :zonas) do
    with :ok <- autorizar_consulta(estado, session_id, actor) do
      zonas =
        estado.zonas_por_codigo
        |> Map.values()
        |> Enum.filter(
          &(actor.rol == :administrador or
              (is_binary(actor.zona_principal) and &1.codigo == actor.zona_principal))
        )
        |> Enum.sort_by(& &1.codigo)

      {:ok, zonas}
    end
  end

  defp consultar_estado(estado, session_id, actor, :albergues) do
    with :ok <- autorizar_consulta(estado, session_id, actor) do
      albergues =
        estado.albergues_por_codigo
        |> Albergues.listar()
        |> Enum.filter(&(actor.rol == :administrador or &1.zona_codigo == actor.zona_principal))
        |> Enum.map(fn albergue ->
          case Albergues.disponibilidad(
                 estado.albergues_por_codigo,
                 estado.estancias_por_id,
                 albergue.codigo
               ) do
            {:ok, disponibilidad} ->
              disponibilidad

            {:error, _motivo} ->
              %{
                albergue: albergue,
                capacidad: albergue.capacidad_maxima,
                ocupadas: 0,
                disponibles: albergue.capacidad_maxima
              }
          end
        end)

      {:ok, albergues}
    end
  end

  defp consultar_estado(estado, session_id, actor, {:personas, filtros}) when is_map(filtros) do
    with {:ok, filtros} <- filtros_por_zona(estado, session_id, actor, filtros) do
      Personas.listar(estado.personas_por_id, filtros)
    end
  end

  defp consultar_estado(estado, session_id, actor, {:persona, id}),
    do: persona_visible(estado, session_id, actor, id)

  defp consultar_estado(estado, session_id, actor, {:personas_por_documento, documento}) do
    with {:ok, personas} <- consultar_estado(estado, session_id, actor, {:personas, %{}}) do
      personas |> Map.new(&{&1.id, &1}) |> Personas.buscar_por_documento(documento)
    end
  end

  defp consultar_estado(estado, session_id, actor, {:historial_persona, id}) do
    with {:ok, _persona} <- persona_visible(estado, session_id, actor, id) do
      Personas.historial(estado.historial_personas, id)
    end
  end

  defp consultar_estado(estado, session_id, actor, {:mensajes_familiares, filtros})
       when is_map(filtros) do
    with {:ok, filtros} <- filtros_por_zona(estado, session_id, actor, filtros),
         {:ok, personas} <-
           Personas.listar(
             estado.personas_por_id,
             Map.take(filtros, [:zona_codigo, "zona_codigo"])
           ) do
      personas_ids = MapSet.new(personas, & &1.id)

      estado.mensajes_por_id
      |> Map.values()
      |> Enum.filter(&MapSet.member?(personas_ids, &1.persona_id))
      |> Enum.filter(
        &(actor.rol != :ciudadano or mensaje_propio?(estado.actividad, &1.id, actor.username))
      )
      |> Map.new(&{&1.id, &1})
      |> Mensajes.listar(filtros)
    end
  end

  defp consultar_estado(_estado, _session_id, _actor, _consulta),
    do: {:error, :consulta_no_reconocida}

  defp filtros_por_zona(estado, session_id, actor, filtros) do
    with :ok <- autorizar_consulta(estado, session_id, actor) do
      if actor.rol == :administrador do
        {:ok, filtros}
      else
        if is_binary(actor.zona_principal) and actor.zona_principal != "" do
          {:ok, Map.put(filtros, :zona_codigo, actor.zona_principal)}
        else
          {:error, :no_autorizado}
        end
      end
    end
  end

  defp persona_visible(estado, session_id, actor, id) do
    with :ok <- autorizar_consulta(estado, session_id, actor),
         {:ok, persona} <- Personas.obtener(estado.personas_por_id, id) do
      if actor.rol == :administrador or
           (is_binary(actor.zona_principal) and actor.zona_principal == persona.zona_codigo),
         do: {:ok, persona},
         else: {:error, :no_encontrado}
    end
  end

  defp mensaje_propio?(actividad, mensaje_id, username) do
    Enum.any?(actividad, fn
      %Emergencias.RegistroActividad{
        accion: :enviar_mensaje_familiar,
        entidad_id: ^mensaje_id,
        username: ^username
      } ->
        true

      _registro ->
        false
    end)
  end

  defp autorizar_cambio_persona(estado, session_id, %{rol: :ciudadano} = actor, persona) do
    autor? =
      Enum.any?(estado.actividad, fn
        %Emergencias.RegistroActividad{
          accion: :reportar_persona,
          entidad_id: id,
          username: username
        } ->
          id == persona.id and username == actor.username

        _registro ->
          false
      end)

    if autor? and
         Sesiones.autorizado_en_zona?(estado, session_id, :reportar_en_zona, persona.zona_codigo),
       do: :ok,
       else: {:error, :no_autorizado}
  end

  defp autorizar_cambio_persona(estado, session_id, _actor, persona),
    do: autorizar_zona(estado, session_id, :cambiar_estado_persona, persona.zona_codigo)

  defp autorizar_consulta(estado, session_id, %{rol: :administrador}) do
    if Sesiones.autorizado?(estado, session_id, :consultar_global),
      do: :ok,
      else: {:error, :no_autorizado}
  end

  defp autorizar_consulta(estado, session_id, _actor) do
    if Sesiones.autorizado?(estado, session_id, :consultar_zona),
      do: :ok,
      else: {:error, :no_autorizado}
  end

  defp autorizar(estado, session_id, permiso) do
    if Sesiones.autorizado?(estado, session_id, permiso),
      do: :ok,
      else: {:error, :no_autorizado}
  end

  defp autorizar_zona(estado, session_id, permiso, zona_codigo) do
    if is_binary(zona_codigo) and
         Sesiones.autorizado_en_zona?(estado, session_id, permiso, zona_codigo) do
      :ok
    else
      {:error, :no_autorizado}
    end
  end

  defp autorizar_reporte(estado, session_id, %{rol: :administrador}, _zona_codigo) do
    if Sesiones.autorizado?(estado, session_id, :reportar_global),
      do: :ok,
      else: {:error, :no_autorizado}
  end

  defp autorizar_reporte(estado, session_id, _actor, zona_codigo),
    do: autorizar_zona(estado, session_id, :reportar_en_zona, zona_codigo)

  defp validar_asignacion(necesidad, recurso, asignaciones, cantidad) do
    cantidad_pendiente = Necesidades.cantidad_pendiente(necesidad, asignaciones)

    cond do
      recurso.zona_codigo != necesidad.zona_codigo ->
        {:error, :zona_incompatible}

      not Necesidades.asignable?(necesidad) ->
        {:error, :transicion_invalida}

      cantidad_pendiente <= 0 ->
        {:error, :cantidad_invalida}

      not cantidad_valida?(cantidad, cantidad_pendiente) ->
        {:error, :cantidad_invalida}

      true ->
        :ok
    end
  end

  defp asignar_necesidad(necesidades, %Necesidad{estado: :pendiente, id: id}),
    do: Necesidades.cambiar_estado(necesidades, id, :asignada)

  defp asignar_necesidad(necesidades, %Necesidad{estado: :asignada}), do: {:ok, necesidades}

  defp validar_cierre(
         %Necesidad{estado: :en_atencion} = necesidad,
         nuevo_estado,
         asignaciones
       ) do
    if enum(nuevo_estado, @necesidades_estados) == :atendida and
         Necesidades.cantidad_pendiente(necesidad, asignaciones) > 0 do
      {:error, :cantidad_invalida}
    else
      :ok
    end
  end

  defp validar_cierre(%Necesidad{}, _nuevo_estado, _asignaciones), do: :ok

  defp actualizar_asignaciones(estado, necesidad_id, :cancelada, actor_username) do
    asignaciones =
      estado.asignaciones_por_id
      |> Map.values()
      |> Enum.filter(
        &(&1.necesidad_id == necesidad_id and &1.estado in [:asignada, :en_atencion])
      )

    Enum.reduce_while(asignaciones, {:ok, estado}, fn asignacion, {:ok, acumulado} ->
      case Recursos.ingresar(
             acumulado.recursos_por_codigo,
             asignacion.recurso_codigo,
             asignacion.cantidad
           ) do
        {:ok, recursos} ->
          fecha = ahora()

          movimiento =
            crear_movimiento(
              nuevo_id("M", acumulado.movimientos_por_id),
              asignacion.recurso_codigo,
              "necesidad:#{necesidad_id}",
              Map.fetch!(recursos, asignacion.recurso_codigo).ubicacion,
              asignacion.cantidad,
              fecha,
              actor_username
            )

          asignacion_actualizada = %{asignacion | estado: :cancelada}

          nuevo = %{
            acumulado
            | recursos_por_codigo: recursos,
              asignaciones_por_id:
                Map.put(acumulado.asignaciones_por_id, asignacion.id, asignacion_actualizada),
              movimientos_por_id: Map.put(acumulado.movimientos_por_id, movimiento.id, movimiento)
          }

          {:cont, {:ok, nuevo}}

        {:error, motivo} ->
          {:halt, {:error, motivo}}
      end
    end)
  end

  defp actualizar_asignaciones(estado, necesidad_id, nuevo_estado, _actor_username)
       when nuevo_estado in [:en_atencion, :atendida] do
    asignaciones =
      Map.new(estado.asignaciones_por_id, fn {id, asignacion} ->
        if asignacion.necesidad_id == necesidad_id and
             asignacion.estado in [:asignada, :en_atencion] do
          {id, %{asignacion | estado: nuevo_estado}}
        else
          {id, asignacion}
        end
      end)

    {:ok, %{estado | asignaciones_por_id: asignaciones}}
  end

  defp actualizar_asignaciones(estado, _necesidad_id, _nuevo_estado, _actor_username),
    do: {:ok, estado}

  defp resumen(estado, necesidades, recursos, zona_codigo) do
    personas =
      estado.personas_por_id
      |> Map.values()
      |> filtrar_por_zona(zona_codigo)

    reportes =
      estado.reportes_mascotas_por_id
      |> Map.values()
      |> filtrar_por_zona(zona_codigo)

    mensajes = mensajes_de_zona(estado, zona_codigo)

    %{
      zona_codigo: zona_codigo,
      necesidades_pendientes: Enum.count(necesidades, &(&1.estado == :pendiente)),
      necesidades: length(necesidades),
      recursos: length(recursos),
      recursos_sin_stock: Enum.count(recursos, &(&1.cantidad_disponible == 0)),
      unidades_disponibles: Enum.reduce(recursos, 0, &(&1.cantidad_disponible + &2)),
      personas_localizadas: Enum.count(personas, &(campo(&1, :estado) == :localizada)),
      mensajes_pendientes: Enum.count(mensajes, &(campo(&1, :estado) == :pendiente)),
      reportes_mascotas_activos:
        Enum.count(reportes, &(campo(&1, :estado) in [:activa, :posible_coincidencia])),
      albergues:
        estado.albergues_por_codigo
        |> Map.values()
        |> filtrar_por_zona(zona_codigo)
        |> length()
    }
  end

  defp mensajes_de_zona(estado, nil), do: Map.values(estado.mensajes_por_id)

  defp mensajes_de_zona(estado, zona_codigo) do
    personas =
      estado.personas_por_id
      |> Map.values()
      |> Enum.filter(&(campo(&1, :zona_codigo) == zona_codigo))
      |> Enum.map(&campo(&1, :id))
      |> MapSet.new()

    estado.mensajes_por_id
    |> Map.values()
    |> Enum.filter(&MapSet.member?(personas, campo(&1, :persona_id)))
  end

  defp filtrar_por_zona(valores, nil), do: valores

  defp filtrar_por_zona(valores, zona),
    do: Enum.filter(valores, &(campo(&1, :zona_codigo) == zona))

  defp campo(%_{} = struct, campo), do: Map.get(struct, campo)

  defp campo(map, campo) when is_map(map),
    do: Map.get(map, campo, Map.get(map, Atom.to_string(campo)))

  defp campo(_valor, _campo), do: nil

  defp construir_zona(attrs) do
    zona = %Emergencias.Zona{
      codigo: valor(attrs, :codigo) |> normalizar_texto(),
      nombre: valor(attrs, :nombre) |> normalizar_texto(),
      nivel_afectacion: enum(valor(attrs, :nivel_afectacion), @zonas_estados),
      personas_estimadas: normalizar_cantidad(valor(attrs, :personas_estimadas))
    }

    {:ok, zona}
  end

  defp construir_sector(attrs) do
    {:ok,
     %Emergencias.Sector{
       codigo: valor(attrs, :codigo) |> normalizar_texto(),
       nombre: valor(attrs, :nombre) |> normalizar_texto()
     }}
  end

  defp construir_punto(attrs) do
    {:ok,
     %Emergencias.PuntoAtencion{
       codigo: valor(attrs, :codigo) |> normalizar_texto(),
       nombre: valor(attrs, :nombre) |> normalizar_texto(),
       personas_estimadas: normalizar_cantidad(valor(attrs, :personas_estimadas)),
       estado: enum(valor(attrs, :estado, :activo), [:activo, :inactivo, :saturado])
     }}
  end

  defp provisionar_administrador(%Estado{usuarios_por_username: usuarios} = estado)
       when map_size(usuarios) > 0,
       do: {:ok, estado, false}

  defp provisionar_administrador(estado) do
    attrs = %{
      username: System.get_env("EMERGENCIAS_ADMIN_USERNAME"),
      password: System.get_env("EMERGENCIAS_ADMIN_PASSWORD"),
      nombre_completo: System.get_env("EMERGENCIAS_ADMIN_NOMBRE"),
      zona_principal: System.get_env("EMERGENCIAS_ADMIN_ZONA")
    }

    credenciales_configuradas? =
      Enum.all?(
        [attrs.username, attrs.password, attrs.nombre_completo],
        &(is_binary(&1) and String.trim(&1) != "")
      )

    configuracion_iniciada? =
      Enum.any?(Map.values(attrs), &(is_binary(&1) and String.trim(&1) != ""))

    if credenciales_configuradas? do
      with {:ok, usuarios} <-
             Usuarios.provisionar_administrador(estado.usuarios_por_username, attrs) do
        {:ok, %{estado | usuarios_por_username: usuarios}, true}
      end
    else
      if configuracion_iniciada?,
        do: {:error, :datos_incompletos},
        else: {:ok, estado, false}
    end
  end

  defp guardar_y_confirmar(coordinador, nuevo_estado, respuesta) do
    case Persistencia.guardar(nuevo_estado, coordinador.ruta) do
      :ok -> {:reply, {:ok, respuesta}, %{coordinador | estado: nuevo_estado}}
      {:error, _motivo} -> {:reply, {:error, :error_persistencia}, coordinador}
    end
  end

  defp registrar_actividad(estado, username, accion, entidad_id) do
    actividad =
      Usuarios.registrar_actividad(
        estado.actividad,
        username,
        accion,
        entidad_id,
        ahora()
      )

    %{estado | actividad: actividad}
  end

  defp crear_movimiento(id, codigo, origen, destino, cantidad, fecha, usuario_id) do
    %MovimientoRecurso{
      id: id,
      recurso_codigo: codigo,
      origen: origen,
      destino: destino,
      cantidad: cantidad,
      fecha: fecha,
      usuario_id: usuario_id
    }
  end

  defp codigo_transferencia(recursos, %Recurso{} = recurso, cantidad) do
    cantidad = normalizar_cantidad(cantidad)

    if is_integer(cantidad) and cantidad < recurso.cantidad_disponible do
      codigo =
        "#{recurso.codigo}-T-#{:crypto.strong_rand_bytes(5) |> Base.url_encode64(padding: false)}"

      if Map.has_key?(recursos, codigo),
        do: codigo_transferencia(recursos, recurso, cantidad),
        else: codigo
    else
      recurso.codigo
    end
  end

  defp nuevo_id(prefijo, mapa) do
    id = "#{prefijo}-#{:crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)}"
    if Map.has_key?(mapa, id), do: nuevo_id(prefijo, mapa), else: id
  end

  defp ahora, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)

  defp cantidad_valida?(cantidad, maximo) do
    cantidad = normalizar_cantidad(cantidad)
    is_integer(cantidad) and cantidad > 0 and cantidad <= maximo
  end

  defp cantidad_positiva(value) do
    value = normalizar_cantidad(value)

    if is_integer(value) and value > 0,
      do: {:ok, value},
      else: {:error, :cantidad_invalida}
  end

  defp enum(value, allowed) when is_atom(value) do
    if value in allowed, do: value, else: nil
  end

  defp enum(value, allowed) when is_binary(value) do
    value = String.trim(value)
    Enum.find(allowed, &(Atom.to_string(&1) == value))
  end

  defp enum(_value, _allowed), do: nil

  defp normalizar_cantidad(value) when is_integer(value), do: value

  defp normalizar_cantidad(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {cantidad, ""} -> cantidad
      _resultado -> nil
    end
  end

  defp normalizar_cantidad(_value), do: nil

  defp normalizar_texto(value) when is_binary(value), do: value |> String.trim() |> empty_to_nil()
  defp normalizar_texto(_value), do: nil

  defp valor(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end
