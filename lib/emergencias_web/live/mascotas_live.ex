defmodule EmergenciasWeb.MascotasLive do
  @moduledoc "Registro y seguimiento de mascotas y revisión de coincidencias mediante la API."
  use EmergenciasWeb, :live_view
  import EmergenciasWeb.MafeComponents
  alias Emergencias.API

  @criterios [
    {:especie, "Especie", 30},
    {:color, "Color", 20},
    {:tamano, "Tamaño", 15},
    {:caracteristicas, "Características", 20},
    {:zona_codigo, "Zona", 10},
    {:nombre, "Nombre", 5}
  ]

  @impl true
  def mount(_params, session, socket) do
    socket =
      assign(socket,
        session_id: session["session_id"],
        usuario: nil,
        zonas: [],
        reportes: [],
        coincidencias: [],
        lista_disponible: false,
        detalle: nil,
        candidatos: [],
        busqueda_realizada: false,
        revision: nil,
        ultima_confirmacion: nil,
        error: nil,
        mensaje: nil,
        filtros: filtros_vacios(),
        registro: registro_vacio()
      )

    {:ok, cargar_sesion(socket)}
  end

  @impl true
  def handle_event("editar_registro", %{"mascota" => attrs}, socket),
    do: {:noreply, assign(socket, registro: attrs)}

  def handle_event("registrar", %{"mascota" => attrs}, socket) do
    socket = assign(socket, registro: attrs, mensaje: nil)

    case API.ejecutar(socket.assigns.session_id, {:reportar_mascota, attrs}) do
      {:ok, reporte} ->
        {:noreply,
         socket
         |> assign(
           registro: registro_vacio(),
           mensaje: "Reporte de mascota registrado.",
           error: nil
         )
         |> cargar_listados()
         |> cargar_detalle(reporte.id)}

      {:error, motivo} ->
        {:noreply, fallar(socket, motivo)}
    end
  end

  def handle_event("filtrar", %{"filtros" => filtros}, socket),
    do:
      {:noreply,
       socket
       |> limpiar_seleccion()
       |> assign(filtros: filtros, mensaje: nil)
       |> cargar_listados()}

  def handle_event("limpiar", _params, socket),
    do:
      {:noreply,
       socket
       |> limpiar_seleccion()
       |> assign(filtros: filtros_vacios(), mensaje: nil)
       |> cargar_listados()}

  def handle_event("detalle", %{"id" => id}, socket),
    do: {:noreply, socket |> assign(mensaje: nil) |> cargar_detalle(id)}

  def handle_event("buscar_coincidencias", %{"id" => id}, socket),
    do: {:noreply, socket |> assign(mensaje: nil) |> cargar_busqueda(id)}

  def handle_event("proponer", %{"perdida" => perdida, "encontrada" => encontrada}, socket) do
    case API.ejecutar(
           socket.assigns.session_id,
           {:proponer_coincidencia_mascota, perdida, encontrada}
         ) do
      {:ok, _coincidencia} ->
        {:noreply,
         socket
         |> assign(
           mensaje: "Coincidencia propuesta. Los reportes permanecen abiertos.",
           error: nil
         )
         |> cargar_listados()
         |> cargar_busqueda(perdida)}

      {:error, motivo} ->
        {:noreply, fallar(socket, motivo)}
    end
  end

  def handle_event("revisar", %{"perdida" => perdida, "encontrada" => encontrada}, socket),
    do: {:noreply, socket |> assign(mensaje: nil) |> cargar_revision(perdida, encontrada)}

  def handle_event("cancelar_revision", _params, socket),
    do: {:noreply, assign(socket, revision: nil)}

  def handle_event("confirmar", _params, %{assigns: %{revision: nil}} = socket),
    do:
      {:noreply,
       assign(socket, error: "Revisa primero los dos reportes antes de confirmar.", mensaje: nil)}

  def handle_event("confirmar", _params, socket) do
    revision = socket.assigns.revision
    comando = {:confirmar_coincidencia_mascota, revision.perdida.id, revision.encontrada.id}

    case API.ejecutar(socket.assigns.session_id, comando) do
      {:ok, coincidencia} ->
        {:noreply,
         socket
         |> limpiar_seleccion()
         |> assign(
           ultima_confirmacion: coincidencia,
           mensaje: "Coincidencia confirmada. Ambos reportes fueron resueltos.",
           error: nil
         )
         |> cargar_listados()}

      {:error, :ya_resuelto} ->
        {:noreply, socket |> limpiar_seleccion() |> cargar_listados() |> fallar(:ya_resuelto)}

      {:error, motivo} ->
        {:noreply, socket |> assign(revision: nil) |> fallar(motivo)}
    end
  end

  def handle_event("reintentar", _params, socket), do: {:noreply, cargar_sesion(socket)}

  defp cargar_sesion(%{assigns: %{session_id: nil}} = socket), do: socket

  defp cargar_sesion(socket) do
    with {:ok, usuario} <- API.consultar(socket.assigns.session_id, :sesion_actual),
         {:ok, zonas} <- API.consultar(socket.assigns.session_id, :zonas) do
      socket |> assign(usuario: usuario, zonas: zonas, error: nil) |> cargar_listados()
    else
      {:error, motivo} -> fallar(socket, motivo)
    end
  end

  defp cargar_listados(socket) do
    with {:ok, reportes} <-
           API.consultar(socket.assigns.session_id, {:reportes_mascotas, socket.assigns.filtros}),
         {:ok, coincidencias} <-
           API.consultar(socket.assigns.session_id, {:coincidencias_mascotas, %{}}) do
      assign(socket,
        reportes: reportes,
        coincidencias: coincidencias,
        lista_disponible: true,
        error: nil
      )
    else
      {:error, motivo} ->
        socket
        |> assign(reportes: [], coincidencias: [], lista_disponible: false)
        |> fallar(motivo)
    end
  end

  defp cargar_detalle(socket, id) do
    socket = limpiar_seleccion(socket)

    case API.consultar(socket.assigns.session_id, {:reporte_mascota, id}) do
      {:ok, reporte} -> assign(socket, detalle: reporte, error: nil)
      {:error, motivo} -> fallar(socket, motivo)
    end
  end

  defp cargar_busqueda(socket, id) do
    socket = limpiar_seleccion(socket)

    with {:ok, reporte} <- API.consultar(socket.assigns.session_id, {:reporte_mascota, id}),
         {:ok, candidatos} <-
           API.consultar(socket.assigns.session_id, {:posibles_coincidencias_mascota, id}) do
      assign(socket,
        detalle: reporte,
        candidatos: candidatos,
        busqueda_realizada: true,
        error: nil
      )
    else
      {:error, motivo} -> fallar(socket, motivo)
    end
  end

  defp cargar_revision(socket, perdida_id, encontrada_id) do
    socket = assign(socket, revision: nil)

    with {:ok, perdida} <-
           API.consultar(socket.assigns.session_id, {:reporte_mascota, perdida_id}),
         {:ok, encontrada} <-
           API.consultar(socket.assigns.session_id, {:reporte_mascota, encontrada_id}),
         {:ok, candidatos} <-
           API.consultar(socket.assigns.session_id, {:posibles_coincidencias_mascota, perdida_id}),
         candidato when not is_nil(candidato) <-
           Enum.find(
             candidatos,
             &(&1.reporte_perdida_id == perdida_id and &1.reporte_encontrada_id == encontrada_id)
           ) do
      assign(socket,
        revision: %{
          perdida: perdida,
          encontrada: encontrada,
          puntaje: candidato.puntaje,
          desglose: candidato.desglose
        },
        error: nil
      )
    else
      nil -> fallar(socket, :tipo_invalido)
      {:error, motivo} -> fallar(socket, motivo)
    end
  end

  defp limpiar_seleccion(socket),
    do: assign(socket, detalle: nil, candidatos: [], busqueda_realizada: false, revision: nil)

  defp fallar(socket, :sesion_invalida) do
    socket
    |> limpiar_seleccion()
    |> assign(
      usuario: nil,
      zonas: [],
      reportes: [],
      coincidencias: [],
      ultima_confirmacion: nil,
      lista_disponible: false,
      mensaje: nil,
      error: mensaje_error(:sesion_invalida)
    )
  end

  defp fallar(socket, :ya_resuelto),
    do:
      assign(socket,
        error: "Uno de los reportes ya está resuelto. No puede vincularse nuevamente.",
        mensaje: nil
      )

  defp fallar(socket, :id_duplicado),
    do:
      assign(socket,
        error: "Esta pareja de reportes ya tiene una propuesta registrada.",
        mensaje: nil
      )

  defp fallar(socket, :tipo_invalido),
    do:
      assign(socket,
        error: "Revisa el tipo de reporte y la compatibilidad de especie de la pareja.",
        mensaje: nil
      )

  defp fallar(socket, :no_autorizado),
    do:
      assign(socket,
        error: "Tu rol o zona no permite realizar esta operación sobre mascotas.",
        mensaje: nil
      )

  defp fallar(socket, motivo), do: assign(socket, error: mensaje_error(motivo), mensaje: nil)

  defp puede_proponer?(%{rol: rol}) when rol in [:voluntario, :coordinador, :administrador],
    do: true

  defp puede_proponer?(_usuario), do: false
  defp puede_confirmar?(%{rol: rol}) when rol in [:coordinador, :administrador], do: true
  defp puede_confirmar?(_usuario), do: false
  defp tipo(:perdida), do: "Perdida"
  defp tipo(:encontrada), do: "Encontrada"
  defp estado(:activa), do: "Activa"
  defp estado(:posible_coincidencia), do: "Posible coincidencia"
  defp estado(:resuelta), do: "Resuelta"
  defp estado(:propuesta), do: "Propuesta"
  defp estado(:confirmada), do: "Confirmada"
  defp fecha(%DateTime{} = fecha), do: Calendar.strftime(fecha, "%d/%m/%Y %H:%M:%S UTC")

  defp filtros_vacios,
    do: %{"tipo_reporte" => "", "especie" => "", "zona_codigo" => "", "estado" => ""}

  defp registro_vacio,
    do: %{
      "tipo_reporte" => "perdida",
      "especie" => "",
      "nombre" => "",
      "caracteristicas" => "",
      "color" => "",
      "tamano" => "",
      "zona_codigo" => "",
      "contacto" => ""
    }

  attr :reporte, :map, required: true

  defp ficha_mascota(assigns) do
    ~H"""
    <div class="rounded-lg border border-slate-200 p-4 text-sm">
      <h3 class="font-semibold">
        {tipo(@reporte.tipo_reporte)} · {@reporte.nombre || "Sin nombre informado"}
      </h3>

      <dl class="mt-3 grid gap-3 sm:grid-cols-2">
        <div>
          <dt class="text-slate-500">Identificador</dt><dd class="break-all">{@reporte.id}</dd>
        </div>

        <div>
          <dt class="text-slate-500">Estado</dt><dd>{estado(@reporte.estado)}</dd>
        </div>

        <div>
          <dt class="text-slate-500">Especie</dt><dd>{@reporte.especie}</dd>
        </div>

        <div>
          <dt class="text-slate-500">Zona</dt><dd>{@reporte.zona_codigo}</dd>
        </div>

        <div>
          <dt class="text-slate-500">Color</dt><dd>{@reporte.color || "Sin información"}</dd>
        </div>

        <div>
          <dt class="text-slate-500">Tamaño</dt><dd>{@reporte.tamano || "Sin información"}</dd>
        </div>

        <div class="sm:col-span-2">
          <dt class="text-slate-500">Características</dt><dd class="whitespace-pre-wrap break-words">
            {@reporte.caracteristicas}
          </dd>
        </div>

        <div class="sm:col-span-2">
          <dt class="text-slate-500">Contacto</dt><dd class="break-words">{@reporte.contacto}</dd>
        </div>
      </dl>
    </div>
    """
  end

  attr :puntaje, :any, required: true
  attr :desglose, :map, required: true

  defp puntaje_similitud(assigns) do
    assigns = assign(assigns, criterios: @criterios)

    ~H"""
    <div class="mt-4 text-sm">
      <p class="font-semibold text-orange-700">Similitud: {@puntaje} / 100 puntos</p>
      <p class="mt-1 text-xs text-slate-500">
        Reconoce variantes de tamaño como «pequeña» y «pequeñita»; los tonos de color relacionados reciben puntaje parcial.
      </p>

      <dl class="mt-3 grid gap-2 sm:grid-cols-2">
        <div
          :for={{campo, etiqueta, maximo} <- @criterios}
          class="flex justify-between gap-3 rounded-lg bg-slate-50 p-2"
        >
          <dt>{etiqueta}</dt><dd>{@desglose[campo]} / {maximo}</dd>
        </div>
      </dl>

      <p class="mt-3 text-slate-600">
        El puntaje ayuda a comparar reportes; no es una probabilidad ni confirma la identidad.
      </p>
    </div>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.modulo
      seccion={:mascotas}
      titulo="Mascotas perdidas y encontradas"
      descripcion="Registro y búsqueda de mascotas con identificación de posibles coincidencias."
      current_user={@current_user}
      csrf_token={@csrf_token}
    >
      <p :if={@mensaje} role="status" class="rounded-lg bg-emerald-100 p-3 text-emerald-900">
        {@mensaje}
      </p>

      <p :if={@error} role="alert" class="rounded-lg bg-rose-100 p-3 text-rose-900">{@error}</p>

      <.tarjeta :if={is_nil(@usuario)} id="acceso-restringido" titulo="Acceso restringido">
        <p class="text-sm text-slate-600">
          Necesitas una sesión activa para consultar y registrar reportes de mascotas.
        </p>

        <a href="/usuarios" class="mt-4 inline-block text-sm font-semibold text-orange-700">Usuarios y permisos →</a>
        <button
          :if={@session_id}
          type="button"
          phx-click="reintentar"
          class="ml-4 rounded-lg border border-slate-300 px-4 py-2 text-sm font-semibold"
        >Reintentar</button>
      </.tarjeta>

      <div :if={@usuario} class="space-y-6">
        <p class="text-sm text-slate-600">
          Sesión: {@usuario.nombre_completo} · {if @usuario.rol == :administrador,
            do: "Alcance global",
            else: "Zona #{@usuario.zona_principal}"}
        </p>

        <.tarjeta id="filtros-mascotas" titulo="Buscar reportes">
          <.form
            for={to_form(@filtros, as: :filtros)}
            id="filtrar-mascotas"
            phx-submit="filtrar"
            class="grid gap-4 md:grid-cols-2"
          >
            <label class="grid gap-1 text-sm font-medium">
              Tipo de reporte
              <select name="filtros[tipo_reporte]" class="rounded-lg border border-slate-300 p-2">
                <option value="">Todos los tipos</option><option
                  :for={tipo <- [:perdida, :encontrada]}
                  value={tipo}
                  selected={@filtros["tipo_reporte"] == to_string(tipo)}
                >
                  {tipo(tipo)}
                </option>
              </select>
            </label>

            <label class="grid gap-1 text-sm font-medium">
              Especie
              <input
                name="filtros[especie]"
                value={@filtros["especie"]}
                class="rounded-lg border border-slate-300 p-2"
              />
            </label>

            <label class="grid gap-1 text-sm font-medium">
              Zona
              <select name="filtros[zona_codigo]" class="rounded-lg border border-slate-300 p-2">
                <option value="">Todas las zonas permitidas</option><option
                  :for={zona <- @zonas}
                  value={zona.codigo}
                  selected={@filtros["zona_codigo"] == zona.codigo}
                >
                  {zona.nombre || zona.codigo}
                </option>
              </select>
            </label>

            <label class="grid gap-1 text-sm font-medium">
              Estado
              <select name="filtros[estado]" class="rounded-lg border border-slate-300 p-2">
                <option value="">Todos los estados</option><option
                  :for={estado <- [:activa, :posible_coincidencia, :resuelta]}
                  value={estado}
                  selected={@filtros["estado"] == to_string(estado)}
                >
                  {estado(estado)}
                </option>
              </select>
            </label>

            <div class="flex flex-wrap gap-3 md:col-span-2">
              <button
                class="rounded-lg bg-orange-700 px-4 py-2 font-semibold text-white hover:bg-orange-800"
                phx-disable-with="Filtrando..."
              >Aplicar filtros</button>
              <button type="button" phx-click="limpiar" class="text-sm font-semibold text-orange-700">Mostrar todos los reportes permitidos</button>
            </div>
          </.form>
        </.tarjeta>

        <.tarjeta id="registro-mascotas" titulo="Registrar mascota perdida o encontrada">
          <.form
            for={to_form(@registro, as: :mascota)}
            id="registrar-mascota"
            phx-change="editar_registro"
            phx-submit="registrar"
            class="grid gap-4 md:grid-cols-2"
          >
            <label class="grid gap-1 text-sm font-medium">
              Tipo de reporte
              <select
                name="mascota[tipo_reporte]"
                required
                class="rounded-lg border border-slate-300 p-2"
              ><option
                :for={tipo <- [:perdida, :encontrada]}
                value={tipo}
                selected={@registro["tipo_reporte"] == to_string(tipo)}
              >
                {tipo(tipo)}
              </option></select>
            </label>

            <label class="grid gap-1 text-sm font-medium">
              Especie
              <input
                name="mascota[especie]"
                value={@registro["especie"]}
                required
                class="rounded-lg border border-slate-300 p-2"
              />
            </label>

            <label class="grid gap-1 text-sm font-medium">
              Nombre (opcional)
              <input
                name="mascota[nombre]"
                value={@registro["nombre"]}
                class="rounded-lg border border-slate-300 p-2"
              />
            </label>

            <label class="grid gap-1 text-sm font-medium">
              Color (opcional)
              <select name="mascota[color]" class="rounded-lg border border-slate-300 p-2">
                <option value="">Sin información</option>
                <option
                  :for={
                    color <- [
                      "negro",
                      "blanco",
                      "gris",
                      "café",
                      "caramelo",
                      "canela",
                      "marrón",
                      "chocolate",
                      "dorado",
                      "atigrado",
                      "otro"
                    ]
                  }
                  value={color}
                  selected={@registro["color"] == color}
                >
                  {String.capitalize(color)}
                </option>
              </select>
            </label>

            <label class="grid gap-1 text-sm font-medium">
              Tamaño (opcional)
              <select name="mascota[tamano]" class="rounded-lg border border-slate-300 p-2">
                <option value="">Sin información</option>
                <option
                  :for={
                    {etiqueta, tamano} <- [
                      {"Muy pequeña", "muy pequeña"},
                      {"Pequeña", "pequeña"},
                      {"Mediana", "mediano"},
                      {"Grande", "grande"},
                      {"Muy grande", "muy grande"}
                    ]
                  }
                  value={tamano}
                  selected={@registro["tamano"] == tamano}
                >
                  {etiqueta}
                </option>
              </select>
            </label>

            <label class="grid gap-1 text-sm font-medium">
              Zona
              <select
                name="mascota[zona_codigo]"
                required
                class="rounded-lg border border-slate-300 p-2"
              ><option value="">Selecciona una zona</option><option
                :for={zona <- @zonas}
                value={zona.codigo}
                selected={@registro["zona_codigo"] == zona.codigo}
              >
                {zona.nombre || zona.codigo}
              </option></select>
            </label>

            <label class="grid gap-1 text-sm font-medium md:col-span-2">
              Características <textarea
                name="mascota[caracteristicas]"
                required
                rows="3"
                class="rounded-lg border border-slate-300 p-2"
              >{@registro["caracteristicas"]}</textarea>
            </label>

            <label class="grid gap-1 text-sm font-medium md:col-span-2">
              Contacto
              <input
                name="mascota[contacto]"
                value={@registro["contacto"]}
                required
                class="rounded-lg border border-slate-300 p-2"
              />
            </label>

            <div class="md:col-span-2">
              <button
                class="rounded-lg bg-orange-700 px-4 py-2 font-semibold text-white hover:bg-orange-800"
                phx-disable-with="Guardando..."
              >Registrar reporte</button>
            </div>
          </.form>
        </.tarjeta>

        <.tarjeta id="listado-mascotas" titulo="Reportes registrados">
          <p :if={!@lista_disponible} class="text-sm text-slate-600">
            No se pudieron cargar los reportes. Revisa el mensaje de error e intenta nuevamente.
          </p>

          <p :if={@lista_disponible && @reportes == []} class="text-sm text-slate-600">
            No hay reportes para mostrar con estos filtros.
          </p>

          <div :if={@lista_disponible && @reportes != []} class="overflow-x-auto">
            <table class="w-full min-w-[600px] text-left text-sm">
              <thead class="border-b border-slate-200 text-slate-500">
                <tr>
                  <th class="py-3 pr-3">Mascota</th><th class="py-3 pr-3">Tipo</th><th class="py-3 pr-3">
                    Zona
                  </th><th class="py-3 pr-3">Estado</th><th class="py-3">Acciones</th>
                </tr>
              </thead>

              <tbody>
                <tr
                  :for={reporte <- @reportes}
                  id={"reporte-#{reporte.id}"}
                  class="border-b border-slate-100"
                >
                  <td class="py-4 pr-3">
                    {reporte.nombre || "Sin nombre informado"} · {reporte.especie}
                  </td><td class="py-4 pr-3">{tipo(reporte.tipo_reporte)}</td><td class="py-4 pr-3">
                    {reporte.zona_codigo}
                  </td><td class="py-4 pr-3">{estado(reporte.estado)}</td>

                  <td class="py-4">
                    <div class="flex flex-wrap gap-3">
                      <button
                        type="button"
                        phx-click="detalle"
                        phx-value-id={reporte.id}
                        class="font-semibold text-orange-700"
                      >Ver detalle</button>
                      <button
                        :if={reporte.estado != :resuelta}
                        type="button"
                        phx-click="buscar_coincidencias"
                        phx-value-id={reporte.id}
                        class="font-semibold text-orange-700"
                        phx-disable-with="Buscando..."
                      >Buscar coincidencias</button>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </.tarjeta>

        <.tarjeta :if={@detalle} id="detalle-mascota" titulo="Detalle del reporte">
          <.ficha_mascota reporte={@detalle} />
        </.tarjeta>

        <.tarjeta
          :if={@busqueda_realizada}
          id="posibles-coincidencias"
          titulo="Posibles coincidencias"
        >
          <p class="mb-4 text-sm text-slate-600">
            Compara el reporte seleccionado con los candidatos. Consultar puntajes no modifica los reportes.
          </p>

          <p :if={@candidatos == []} class="text-sm text-slate-600">
            No hay reportes compatibles disponibles dentro de tu alcance.
          </p>

          <div class="space-y-4">
            <article
              :for={candidato <- @candidatos}
              id={"candidato-#{candidato.reporte.id}"}
              class="rounded-lg border border-slate-200 p-4"
            >
              <.ficha_mascota reporte={candidato.reporte} />
              <.puntaje_similitud puntaje={candidato.puntaje} desglose={candidato.desglose} />
              <div class="mt-4 flex flex-wrap gap-3">
                <button
                  :if={puede_proponer?(@usuario)}
                  type="button"
                  phx-click="proponer"
                  phx-value-perdida={candidato.reporte_perdida_id}
                  phx-value-encontrada={candidato.reporte_encontrada_id}
                  class="rounded-lg bg-orange-700 px-4 py-2 text-sm font-semibold text-white hover:bg-orange-800"
                  phx-disable-with="Proponiendo..."
                >Proponer coincidencia</button>
                <button
                  :if={puede_confirmar?(@usuario)}
                  type="button"
                  phx-click="revisar"
                  phx-value-perdida={candidato.reporte_perdida_id}
                  phx-value-encontrada={candidato.reporte_encontrada_id}
                  class="rounded-lg border border-slate-300 px-4 py-2 text-sm font-semibold"
                >Revisar pareja</button>
              </div>
            </article>
          </div>
        </.tarjeta>

        <.tarjeta :if={@revision} id="revision-coincidencia" titulo="Revisar antes de confirmar">
          <p class="mb-4 text-sm text-slate-600">
            Verifica los identificadores, características y contactos de ambos reportes. Confirmar resolverá los dos reportes.
          </p>

          <div class="grid gap-4 lg:grid-cols-2">
            <.ficha_mascota reporte={@revision.perdida} /><.ficha_mascota reporte={
              @revision.encontrada
            } />
          </div>
          <.puntaje_similitud puntaje={@revision.puntaje} desglose={@revision.desglose} />
          <div class="mt-4 flex flex-wrap gap-3">
            <button
              :if={puede_confirmar?(@usuario)}
              id="confirmar-coincidencia"
              type="button"
              phx-click="confirmar"
              data-confirm="¿Confirmas la coincidencia y el cierre de ambos reportes?"
              class="rounded-lg bg-orange-700 px-4 py-2 font-semibold text-white hover:bg-orange-800"
              phx-disable-with="Confirmando..."
            >Confirmar coincidencia y resolver ambos reportes</button>
            <button
              type="button"
              phx-click="cancelar_revision"
              class="rounded-lg border border-slate-300 px-4 py-2 text-sm font-semibold"
            >Cancelar revisión</button>
          </div>
        </.tarjeta>

        <.tarjeta :if={@ultima_confirmacion} id="cierre-coincidencia" titulo="Coincidencia confirmada">
          <p class="text-sm text-slate-600">Ambos reportes quedaron resueltos.</p>

          <dl class="mt-3 space-y-2 text-sm">
            <div>
              <dt class="font-semibold">Reporte de pérdida</dt><dd class="break-all">
                {@ultima_confirmacion.reporte_perdida_id}
              </dd>
            </div><div>
              <dt class="font-semibold">Reporte de hallazgo</dt><dd class="break-all">
                {@ultima_confirmacion.reporte_encontrada_id}
              </dd>
            </div><div>
              <dt class="font-semibold">Confirmada por</dt><dd>
                {@ultima_confirmacion.confirmada_por}
              </dd>
            </div>
          </dl>
        </.tarjeta>

        <.tarjeta id="coincidencias-registradas" titulo="Coincidencias registradas">
          <p :if={!@lista_disponible} class="text-sm text-slate-600">
            No se pudieron cargar las coincidencias.
          </p>

          <p :if={@lista_disponible && @coincidencias == []} class="text-sm text-slate-600">
            No hay coincidencias registradas dentro de tu alcance.
          </p>

          <div :if={@lista_disponible} class="space-y-4">
            <article
              :for={coincidencia <- @coincidencias}
              id={"coincidencia-#{coincidencia.id}"}
              class="rounded-lg border border-slate-200 p-4 text-sm"
            >
              <p class="font-semibold">
                {estado(coincidencia.estado)} · {coincidencia.puntaje} / 100 puntos
              </p>

              <p class="mt-2 break-all">Pérdida: {coincidencia.reporte_perdida_id}</p><p class="break-all">
                Hallazgo: {coincidencia.reporte_encontrada_id}
              </p>

              <p class="mt-2 text-slate-600">{fecha(coincidencia.fecha)}</p>

              <p :if={coincidencia.confirmada_por} class="text-slate-600">
                Confirmada por: {coincidencia.confirmada_por}
              </p>

              <button
                :if={coincidencia.estado == :propuesta && puede_confirmar?(@usuario)}
                type="button"
                phx-click="revisar"
                phx-value-perdida={coincidencia.reporte_perdida_id}
                phx-value-encontrada={coincidencia.reporte_encontrada_id}
                class="mt-3 font-semibold text-orange-700"
              >Revisar pareja</button>
            </article>
          </div>
        </.tarjeta>
      </div>
    </.modulo>
    """
  end
end
