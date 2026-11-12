defmodule Emergencias.PersonasIntegracionTest do
  use ExUnit.Case, async: false
  alias Emergencias.{API, Estado, EstadoServidor, Persistencia, Usuario, Zona}

  setup do
    ruta =
      Path.join(System.tmp_dir!(), "personas-#{System.unique_integer([:positive])}/estado.json")

    usuarios =
      Map.new(
        [
          {"ana", :ciudadano, "Z1"},
          {"otro", :ciudadano, "Z1"},
          {"vol", :voluntario, "Z1"},
          {"coord", :coordinador, "Z1"},
          {"admin", :administrador, "Z2"},
          {"fuera", :voluntario, "Z2"}
        ],
        fn {nombre, rol, zona} ->
          {nombre, %Usuario{username: nombre, rol: rol, zona_principal: zona}}
        end
      )

    sesiones = Map.new(usuarios, fn {nombre, _usuario} -> {nombre, nombre} end)

    estado = %Estado{
      usuarios_por_username: usuarios,
      zonas_por_codigo: %{"Z1" => %Zona{codigo: "Z1"}, "Z2" => %Zona{codigo: "Z2"}}
    }

    assert :ok = Persistencia.guardar(estado, ruta)
    start_supervised!({EstadoServidor, path: ruta})
    # Las sesiones son transitorias: se instalan solo en el proceso aislado de prueba.
    :sys.replace_state(EstadoServidor, fn servidor ->
      %{servidor | estado: %{servidor.estado | sesiones: sesiones}}
    end)

    on_exit(fn -> File.rm_rf!(Path.dirname(ruta)) end)
    %{ruta: ruta}
  end

  defp registrar(usuario \\ "ana", zona \\ "Z1") do
    API.ejecutar(
      usuario,
      {:reportar_persona,
       %{nombre: "Ana", edad: 20, documento_referencia: "123", zona_codigo: zona}}
    )
  end

  test "alta auditada, cambio e historial sobreviven al snapshot", %{ruta: ruta} do
    assert {:ok, persona} = registrar()

    assert {:ok, actualizada} =
             API.ejecutar("ana", {:cambiar_estado_persona, persona.id, :localizada})

    assert actualizada.estado == :localizada
    assert {:ok, [cambio]} = API.consultar("ana", {:historial_persona, persona.id})
    assert cambio.usuario_id == "ana"
    assert {:ok, estado} = Persistencia.cargar(ruta)
    assert estado.personas_por_id[persona.id] == actualizada
    assert estado.historial_personas == [cambio]

    assert Enum.any?(
             estado.actividad,
             &(&1.accion == :reportar_persona and &1.entidad_id == persona.id and
                 &1.username == "ana")
           )

    assert estado.sesiones == %{}
  end

  test "restringe consultas y cambios por rol, zona y autoría" do
    assert {:ok, persona} = registrar()

    assert {:error, :no_autorizado} =
             API.ejecutar("otro", {:cambiar_estado_persona, persona.id, :localizada})

    assert {:error, :no_encontrado} = API.consultar("fuera", {:persona, persona.id})
    assert {:error, :no_encontrado} = API.consultar("fuera", {:historial_persona, persona.id})
    assert {:ok, []} = API.consultar("fuera", {:personas_por_documento, "123"})
    assert {:ok, []} = API.consultar("fuera", {:personas, %{"zona_codigo" => "Z1"}})
    assert {:error, :no_autorizado} = registrar("ana", "Z2")
    assert {:error, :sesion_invalida} = API.consultar("invalida", {:persona, persona.id})

    for {usuario, estado} <- [
          {"vol", :localizada},
          {"coord", :trasladada},
          {"admin", :reunificada}
        ] do
      assert {:ok, _} = API.ejecutar(usuario, {:cambiar_estado_persona, persona.id, estado})
    end

    assert {:error, :ya_resuelto} =
             API.ejecutar("admin", {:cambiar_estado_persona, persona.id, :reportada})

    assert {:ok, [_]} = API.consultar("admin", {:personas_por_documento, "123"})
  end

  test "no concede autoría sin registro de alta" do
    assert {:ok, persona} = registrar()

    :sys.replace_state(EstadoServidor, fn servidor ->
      %{servidor | estado: %{servidor.estado | actividad: []}}
    end)

    assert {:error, :no_autorizado} =
             API.ejecutar("ana", {:cambiar_estado_persona, persona.id, :localizada})
  end

  test "el registro ignora identidad e ID enviados por el formulario" do
    attrs = %{
      "id" => "inventado",
      "nombre" => "Ana",
      "edad" => "0",
      "documento_referencia" => "123",
      "zona_codigo" => "Z1",
      "username" => "otro",
      "usuario_id" => "otro",
      "rol" => "administrador"
    }

    assert {:ok, persona} = API.ejecutar("ana", {:reportar_persona, attrs})
    refute persona.id == "inventado"

    assert {:error, :no_autorizado} =
             API.ejecutar("otro", {:cambiar_estado_persona, persona.id, :localizada})

    assert {:ok, _} = API.ejecutar("ana", {:cambiar_estado_persona, persona.id, :localizada})
  end

  test "una falla de persistencia conserva persona e historial", %{ruta: ruta} do
    assert {:ok, persona} = registrar()
    # Un archivo como directorio padre causa una falla de escritura reproducible.
    :sys.replace_state(EstadoServidor, &%{&1 | ruta: Path.join(ruta, "imposible.json")})

    assert {:error, :error_persistencia} =
             API.ejecutar("ana", {:cambiar_estado_persona, persona.id, :localizada})

    assert {:ok, ^persona} = API.consultar("ana", {:persona, persona.id})
    assert {:ok, []} = API.consultar("ana", {:historial_persona, persona.id})
  end

  test "dos cambios simultáneos al mismo estado generan un solo historial" do
    assert {:ok, persona} = registrar()

    resultados =
      1..2
      |> Task.async_stream(fn _ ->
        API.ejecutar("vol", {:cambiar_estado_persona, persona.id, :localizada})
      end)
      |> Enum.map(fn {:ok, resultado} -> resultado end)

    assert Enum.count(resultados, &match?({:ok, _}, &1)) == 1
    assert {:error, :transicion_invalida} in resultados
    assert {:ok, [_]} = API.consultar("ana", {:historial_persona, persona.id})
  end
end
