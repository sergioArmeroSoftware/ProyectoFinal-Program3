defmodule Emergencias.MensajesIntegracionTest do
  use ExUnit.Case, async: false
  alias Emergencias.{API, Estado, EstadoServidor, Persistencia, PersonaAfectada, Usuario, Zona}

  setup do
    ruta =
      Path.join(System.tmp_dir!(), "mensajes-#{System.unique_integer([:positive])}/estado.json")

    usuarios =
      Map.new(
        [
          {"ana", :ciudadano, "Z-01"},
          {"otro", :ciudadano, "Z-01"},
          {"vol", :voluntario, "Z-01"},
          {"coord", :coordinador, "Z-01"},
          {"admin", :administrador, "Z-02"},
          {"fuera", :voluntario, "Z-02"}
        ],
        fn {nombre, rol, zona} ->
          {nombre, %Usuario{username: nombre, rol: rol, zona_principal: zona}}
        end
      )

    estado = %Estado{
      usuarios_por_username: usuarios,
      zonas_por_codigo: %{"Z-01" => %Zona{codigo: "Z-01"}, "Z-02" => %Zona{codigo: "Z-02"}},
      personas_por_id: %{
        "P1" => %PersonaAfectada{id: "P1", zona_codigo: "Z-01"},
        "P2" => %PersonaAfectada{id: "P2", zona_codigo: "Z-02"}
      }
    }

    assert :ok = Persistencia.guardar(estado, ruta)
    start_supervised!({EstadoServidor, path: ruta})
    sesiones = Map.new(usuarios, fn {nombre, _usuario} -> {nombre, nombre} end)
    # Las sesiones solo existen en este proceso aislado de prueba.
    :sys.replace_state(EstadoServidor, fn servidor ->
      %{servidor | estado: %{servidor.estado | sesiones: sesiones}}
    end)

    on_exit(fn -> File.rm_rf!(Path.dirname(ruta)) end)
    %{ruta: ruta}
  end

  defp enviar(usuario \\ "ana", persona_id \\ "P1") do
    API.ejecutar(
      usuario,
      {:enviar_mensaje_familiar, persona_id,
       %{remitente: "otro", destinatario: "otro", contenido: "Estoy bien"}}
    )
  end

  test "creación auditada y entrega persistida", %{ruta: ruta} do
    assert {:ok, mensaje} = enviar()
    assert mensaje.estado == :pendiente
    assert {:ok, estado} = Persistencia.cargar(ruta)
    assert estado.mensajes_por_id[mensaje.id] == mensaje

    assert Enum.any?(
             estado.actividad,
             &(&1.accion == :enviar_mensaje_familiar and &1.entidad_id == mensaje.id and
                 &1.username == "ana")
           )

    assert {:ok, entregado} = API.ejecutar("vol", {:marcar_mensaje_entregado, mensaje.id})
    assert entregado.estado == :entregado
    assert {:error, :ya_resuelto} = API.ejecutar("coord", {:marcar_mensaje_entregado, mensaje.id})
    assert {:ok, estado} = Persistencia.cargar(ruta)
    assert estado.mensajes_por_id[mensaje.id] == entregado
    assert estado.sesiones == %{}
    assert Enum.count(estado.actividad, &(&1.accion == :marcar_mensaje_entregado)) == 1
  end

  test "ciudadanos no entregan, aunque sean autores o figuren como destinatarios" do
    assert {:ok, mensaje} = enviar()

    for usuario <- ["ana", "otro"] do
      assert {:error, :no_autorizado} =
               API.ejecutar(usuario, {:marcar_mensaje_entregado, mensaje.id})
    end

    assert {:ok, [^mensaje]} = API.consultar("ana", {:mensajes_familiares, %{}})
    assert {:ok, []} = API.consultar("otro", {:mensajes_familiares, %{persona_id: "P1"}})

    assert {:ok, [^mensaje]} =
             API.consultar("coord", {:mensajes_familiares, %{estado: :pendiente}})
  end

  test "restringe por zona e identidad, incluso con filtros manipulados" do
    assert {:ok, mensaje} = enviar()
    assert {:error, :no_encontrado} = enviar("ana", "P2")
    assert {:error, :no_encontrado} = enviar("ana", "inexistente")
    assert {:error, :sesion_invalida} = enviar("invalida")

    assert {:error, :no_encontrado} =
             API.ejecutar("fuera", {:marcar_mensaje_entregado, mensaje.id})

    assert {:ok, []} =
             API.consultar(
               "fuera",
               {:mensajes_familiares, %{"zona_codigo" => "Z-01", "persona_id" => "P1"}}
             )

    assert {:ok, [^mensaje]} =
             API.consultar("admin", {:mensajes_familiares, %{zona_codigo: "Z-01"}})

    assert {:ok, []} = API.consultar("admin", {:mensajes_familiares, %{zona_codigo: "Z-02"}})
    assert {:ok, _} = API.ejecutar("admin", {:marcar_mensaje_entregado, mensaje.id})
    assert {:ok, []} = API.consultar("vol", {:mensajes_familiares, %{estado: "pendiente"}})
    assert {:ok, [_]} = API.consultar("vol", {:mensajes_familiares, %{estado: "entregado"}})
  end

  test "sin evidencia o con evidencia de otra operación no se concede autoría" do
    assert {:ok, mensaje} = enviar()

    :sys.replace_state(EstadoServidor, fn servidor ->
      actividad = Enum.map(servidor.estado.actividad, &%{&1 | accion: :reportar_persona})
      %{servidor | estado: %{servidor.estado | actividad: actividad}}
    end)

    assert {:ok, []} = API.consultar("ana", {:mensajes_familiares, %{}})
    assert {:ok, [^mensaje]} = API.consultar("vol", {:mensajes_familiares, %{}})
  end

  test "el coordinador genera ID y fecha y rechaza datos inválidos" do
    attrs = %{
      "id" => "falso",
      "fecha" => "falsa",
      "persona_id" => "P2",
      "estado" => "entregado",
      "username" => "otro",
      "remitente" => "Ana",
      "destinatario" => "Luis",
      "contenido" => "Hola"
    }

    assert {:ok, mensaje} = API.ejecutar("ana", {:enviar_mensaje_familiar, "P1", attrs})
    refute mensaje.id == "falso"
    assert %DateTime{} = mensaje.fecha
    assert mensaje.persona_id == "P1"
    assert mensaje.estado == :pendiente
    assert {:ok, [^mensaje]} = API.consultar("ana", {:mensajes_familiares, %{}})

    assert {:error, :datos_incompletos} =
             API.ejecutar("ana", {:enviar_mensaje_familiar, "P1", %{attrs | "contenido" => " "}})

    assert {:error, :estado_invalido} =
             API.consultar("ana", {:mensajes_familiares, %{estado: "otro"}})

    assert {:error, :no_encontrado} =
             API.ejecutar("vol", {:marcar_mensaje_entregado, "inexistente"})
  end

  test "una falla de escritura conserva mensajes y actividad", %{ruta: ruta} do
    assert {:ok, mensaje} = enviar()
    assert {:ok, anterior} = Persistencia.cargar(ruta)
    :sys.replace_state(EstadoServidor, &%{&1 | ruta: Path.join(ruta, "imposible.json")})

    assert {:error, :error_persistencia} =
             API.ejecutar("vol", {:marcar_mensaje_entregado, mensaje.id})

    assert {:error, :error_persistencia} = enviar()
    assert {:ok, [^mensaje]} = API.consultar("vol", {:mensajes_familiares, %{}})
    assert {:ok, ^anterior} = Persistencia.cargar(ruta)
    assert :sys.get_state(EstadoServidor).estado.actividad == anterior.actividad
  end

  test "dos entregas simultáneas registran una sola confirmación", %{ruta: ruta} do
    assert {:ok, mensaje} = enviar()

    resultados =
      1..2
      |> Task.async_stream(fn _ ->
        API.ejecutar("vol", {:marcar_mensaje_entregado, mensaje.id})
      end)
      |> Enum.map(fn {:ok, resultado} -> resultado end)

    assert Enum.count(resultados, &match?({:ok, _}, &1)) == 1
    assert {:error, :ya_resuelto} in resultados
    assert {:ok, estado} = Persistencia.cargar(ruta)
    assert estado.mensajes_por_id[mensaje.id].estado == :entregado
    assert Enum.count(estado.actividad, &(&1.accion == :marcar_mensaje_entregado)) == 1
  end
end
