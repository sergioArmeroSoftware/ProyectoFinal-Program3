defmodule Emergencias.MascotasIntegracionTest do
  use ExUnit.Case, async: false

  alias Emergencias.{
    API,
    Estado,
    EstadoServidor,
    Persistencia,
    Usuario,
    Usuarios,
    Zona,
    PersonaAfectada,
    MensajeFamiliar
  }

  setup do
    ruta =
      Path.join(System.tmp_dir!(), "mascotas-#{System.unique_integer([:positive])}/estado.json")

    usuarios =
      Map.new(
        [
          {"ana", :ciudadano, "Z1"},
          {"vol", :voluntario, "Z1"},
          {"coord", :coordinador, "Z1"},
          {"admin", :administrador, "Z2"},
          {"fuera", :coordinador, "Z2"}
        ],
        fn {nombre, rol, zona} ->
          {nombre, %Usuario{username: nombre, rol: rol, zona_principal: zona}}
        end
      )

    persona = %PersonaAfectada{id: "P1", zona_codigo: "Z1", nombre: "Ana", edad: 20}

    mensaje = %MensajeFamiliar{
      id: "M1",
      persona_id: "P1",
      fecha: ~U[2026-01-01 00:00:00Z],
      remitente: "Familia",
      destinatario: "Ana",
      contenido: "Hola"
    }

    estado = %Estado{
      usuarios_por_username: usuarios,
      zonas_por_codigo: %{"Z1" => %Zona{codigo: "Z1"}, "Z2" => %Zona{codigo: "Z2"}},
      personas_por_id: %{"P1" => persona},
      mensajes_por_id: %{"M1" => mensaje}
    }

    assert :ok = Persistencia.guardar(estado, ruta)
    start_supervised!({EstadoServidor, path: ruta})
    sesiones = Map.new(usuarios, fn {nombre, _usuario} -> {nombre, nombre} end)
    # Solo instala sesiones en el coordinador aislado de prueba.
    :sys.replace_state(EstadoServidor, fn servidor ->
      %{servidor | estado: %{servidor.estado | sesiones: sesiones}}
    end)

    on_exit(fn ->
      File.rm(ruta)
      File.rmdir(Path.dirname(ruta))
    end)

    %{ruta: ruta, inicial: estado}
  end

  defp registrar(tipo, usuario \\ "ana", zona \\ "Z1", cambios \\ %{}) do
    attrs = %{
      tipo_reporte: tipo,
      especie: "perro",
      nombre: "Luna",
      caracteristicas: "mancha blanca",
      color: "negro",
      tamano: "mediano",
      zona_codigo: zona,
      contacto: "Familia"
    }

    API.ejecutar(usuario, {:reportar_mascota, Map.merge(attrs, cambios)})
  end

  defp pareja do
    {:ok, perdida} = registrar(:perdida)
    {:ok, encontrada} = registrar(:encontrada)
    {perdida, encontrada}
  end

  defp confirmar(usuario, perdida, encontrada),
    do: API.ejecutar(usuario, {:confirmar_coincidencia_mascota, perdida.id, encontrada.id})

  defp proponer(usuario, perdida, encontrada),
    do: API.ejecutar(usuario, {:proponer_coincidencia_mascota, perdida.id, encontrada.id})

  test "alta, filtros y consulta de puntajes no modifican estados", %{ruta: ruta} do
    {perdida, encontrada} = pareja()
    assert perdida.estado == :activa

    assert {:ok, [^perdida]} =
             API.consultar(
               "ana",
               {:reportes_mascotas, %{tipo_reporte: :perdida, especie: "PERRO", estado: :activa}}
             )

    assert {:ok, ^perdida} = API.consultar("ana", {:reporte_mascota, perdida.id})
    assert {:ok, antes} = Persistencia.cargar(ruta)

    assert {:ok, [resultado]} =
             API.consultar("ana", {:posibles_coincidencias_mascota, perdida.id})

    assert resultado.puntaje == 100.0
    assert resultado.reporte.id == encontrada.id
    assert {:ok, ^antes} = Persistencia.cargar(ruta)
    assert {:ok, []} = API.consultar("ana", {:coincidencias_mascotas, %{}})
  end

  test "el voluntario propone y el coordinador confirma ambos reportes", %{
    ruta: ruta,
    inicial: inicial
  } do
    {perdida, encontrada} = pareja()
    assert Usuarios.permitido?(:voluntario, :proponer_coincidencia)
    assert Usuarios.permitido?(:coordinador, :confirmar_coincidencia)
    assert {:ok, propuesta} = proponer("vol", perdida, encontrada)
    assert propuesta.estado == :propuesta

    for id <- [perdida.id, encontrada.id] do
      assert {:ok, %{estado: :posible_coincidencia}} =
               API.consultar("ana", {:reporte_mascota, id})
    end

    assert {:error, :id_duplicado} = proponer("coord", perdida, encontrada)
    assert {:ok, confirmada} = confirmar("coord", perdida, encontrada)
    assert confirmada.id == propuesta.id
    assert confirmada.confirmada_por == "coord"
    assert confirmada.estado == :confirmada
    assert %DateTime{} = confirmada.fecha
    assert {:ok, estado} = Persistencia.cargar(ruta)
    assert estado.reportes_mascotas_por_id[perdida.id].estado == :resuelta
    assert estado.reportes_mascotas_por_id[encontrada.id].estado == :resuelta
    assert estado.coincidencias_mascotas_por_id == %{confirmada.id => confirmada}
    assert estado.personas_por_id == inicial.personas_por_id
    assert estado.mensajes_por_id == inicial.mensajes_por_id

    assert Enum.any?(
             estado.actividad,
             &(&1.accion == :confirmar_coincidencia_mascota and &1.username == "coord" and
                 &1.entidad_id == confirmada.id)
           )

    assert {:error, :ya_resuelto} = confirmar("coord", perdida, encontrada)
    assert {:ok, []} = API.consultar("ana", {:reportes_mascotas, %{estado: :activa}})

    assert {:error, :ya_resuelto} =
             API.consultar("ana", {:posibles_coincidencias_mascota, perdida.id})
  end

  test "ciudadanos no proponen ni confirman y los voluntarios no confirman" do
    {perdida, encontrada} = pareja()
    assert {:error, :no_autorizado} = proponer("ana", perdida, encontrada)

    for usuario <- ["ana", "vol"] do
      assert {:error, :no_autorizado} = confirmar(usuario, perdida, encontrada)
    end

    assert {:error, :sesion_invalida} = confirmar("invalida", perdida, encontrada)
    assert {:ok, %{estado: :activa}} = API.consultar("ana", {:reporte_mascota, perdida.id})
    assert {:ok, _} = confirmar("admin", perdida, encontrada)
  end

  test "ambos reportes deben estar en alcance; el administrador opera globalmente" do
    {perdida, encontrada} = pareja()
    assert {:ok, otra_zona} = registrar(:encontrada, "fuera", "Z2")
    assert {:error, :no_autorizado} = registrar(:perdida, "ana", "Z2")
    assert {:error, :no_encontrado} = API.consultar("fuera", {:reporte_mascota, perdida.id})

    assert {:ok, [^otra_zona]} =
             API.consultar("fuera", {:reportes_mascotas, %{"zona_codigo" => "Z1"}})

    assert {:error, :no_encontrado} = proponer("vol", perdida, otra_zona)
    assert {:error, :no_encontrado} = confirmar("coord", perdida, otra_zona)
    assert {:error, :no_encontrado} = confirmar("fuera", perdida, encontrada)
    assert {:ok, resultados} = API.consultar("ana", {:posibles_coincidencias_mascota, perdida.id})
    refute Enum.any?(resultados, &(&1.reporte.id == otra_zona.id))
    assert {:ok, _} = proponer("admin", perdida, otra_zona)
    assert {:ok, []} = API.consultar("ana", {:coincidencias_mascotas, %{}})

    assert {:ok, [_]} =
             API.consultar("admin", {:coincidencias_mascotas, %{reporte_id: perdida.id}})

    assert {:ok, _} = confirmar("admin", perdida, otra_zona)
  end

  test "rechaza parejas incompatibles y no confía en atributos de identidad" do
    {perdida, encontrada} = pareja()
    assert {:ok, gato} = registrar(:encontrada, "ana", "Z1", %{especie: "gato"})
    assert {:error, :tipo_invalido} = confirmar("coord", perdida, gato)
    assert {:error, :tipo_invalido} = proponer("vol", perdida, perdida)

    assert {:error, :no_encontrado} =
             API.ejecutar("coord", {:confirmar_coincidencia_mascota, perdida.id, "otro"})

    assert {:error, :datos_incompletos} = registrar(:perdida, "ana", "Z1", %{contacto: " "})
    assert {:error, :tipo_invalido} = registrar(:otro)

    assert {:ok, reporte} =
             registrar(:perdida, "ana", "Z1", %{id: "falso", estado: :resuelta, username: "admin"})

    refute reporte.id == "falso"
    assert reporte.estado == :activa
    assert {:error, :no_autorizado} = confirmar("ana", reporte, encontrada)
  end

  test "conserva propuestas alternativas pero bloquea confirmaciones contradictorias" do
    {perdida, encontrada} = pareja()
    assert {:ok, otra} = registrar(:encontrada)
    assert {:ok, _} = proponer("vol", perdida, encontrada)
    assert {:ok, _} = proponer("vol", perdida, otra)
    assert {:ok, _} = confirmar("coord", perdida, encontrada)
    assert {:error, :ya_resuelto} = confirmar("coord", perdida, otra)
    assert {:error, :ya_resuelto} = proponer("vol", perdida, otra)

    assert {:ok, %{estado: :posible_coincidencia}} =
             API.consultar("ana", {:reporte_mascota, otra.id})

    assert {:ok, [_]} = API.consultar("ana", {:coincidencias_mascotas, %{estado: :propuesta}})
    assert {:ok, [_]} = API.consultar("ana", {:coincidencias_mascotas, %{estado: :confirmada}})
  end

  test "fallar el guardado no confirma ni cambia parcialmente los reportes", %{ruta: ruta} do
    {perdida, encontrada} = pareja()
    assert {:ok, _} = proponer("vol", perdida, encontrada)
    assert {:ok, anterior} = Persistencia.cargar(ruta)
    :sys.replace_state(EstadoServidor, &%{&1 | ruta: Path.join(ruta, "imposible.json")})
    assert {:error, :error_persistencia} = confirmar("coord", perdida, encontrada)
    actual = :sys.get_state(EstadoServidor).estado
    assert actual.reportes_mascotas_por_id == anterior.reportes_mascotas_por_id
    assert actual.coincidencias_mascotas_por_id == anterior.coincidencias_mascotas_por_id
    assert actual.actividad == anterior.actividad
    assert {:ok, ^anterior} = Persistencia.cargar(ruta)
  end

  test "fallar el guardado de altas y propuestas conserva todo el estado", %{ruta: ruta} do
    {perdida, encontrada} = pareja()
    assert {:ok, anterior} = Persistencia.cargar(ruta)
    :sys.replace_state(EstadoServidor, &%{&1 | ruta: Path.join(ruta, "imposible.json")})
    assert {:error, :error_persistencia} = registrar(:perdida)
    assert {:error, :error_persistencia} = proponer("vol", perdida, encontrada)
    actual = :sys.get_state(EstadoServidor).estado
    assert %{actual | sesiones: %{}} == anterior
    assert {:ok, ^anterior} = Persistencia.cargar(ruta)
  end

  test "dos confirmaciones concurrentes de la misma pareja se confirman una sola vez", %{
    ruta: ruta
  } do
    {perdida, encontrada} = pareja()

    resultados =
      1..2
      |> Task.async_stream(fn _ -> confirmar("coord", perdida, encontrada) end)
      |> Enum.map(fn {:ok, resultado} -> resultado end)

    assert Enum.count(resultados, &match?({:ok, _}, &1)) == 1
    assert {:error, :ya_resuelto} in resultados
    assert {:ok, estado} = Persistencia.cargar(ruta)
    assert map_size(estado.coincidencias_mascotas_por_id) == 1
    assert Enum.all?(estado.reportes_mascotas_por_id, fn {_id, r} -> r.estado == :resuelta end)
  end

  test "confirmaciones concurrentes que comparten un reporte no cierran dos parejas", %{
    ruta: ruta
  } do
    {perdida, encontrada} = pareja()
    assert {:ok, otra} = registrar(:encontrada)

    resultados =
      [encontrada, otra]
      |> Task.async_stream(&confirmar("coord", perdida, &1))
      |> Enum.map(fn {:ok, resultado} -> resultado end)

    assert Enum.count(resultados, &match?({:ok, _}, &1)) == 1
    assert {:error, :ya_resuelto} in resultados
    assert {:ok, estado} = Persistencia.cargar(ruta)
    assert map_size(estado.coincidencias_mascotas_por_id) == 1

    assert Enum.count(estado.reportes_mascotas_por_id, fn {_id, r} -> r.estado == :resuelta end) ==
             2

    assert Enum.count(estado.reportes_mascotas_por_id, fn {_id, r} -> r.estado == :activa end) ==
             1
  end

  test "reiniciar recupera ambos cierres y la coincidencia sin sesiones", %{ruta: ruta} do
    {perdida, encontrada} = pareja()
    assert {:ok, confirmada} = confirmar("coord", perdida, encontrada)
    assert :ok = stop_supervised(EstadoServidor)
    start_supervised!({EstadoServidor, path: ruta})
    estado = :sys.get_state(EstadoServidor).estado
    assert estado.coincidencias_mascotas_por_id[confirmada.id] == confirmada
    assert estado.reportes_mascotas_por_id[perdida.id].estado == :resuelta
    assert estado.reportes_mascotas_por_id[encontrada.id].estado == :resuelta
    assert estado.sesiones == %{}
    assert {:error, :sesion_invalida} = API.consultar("ana", {:reporte_mascota, perdida.id})
  end

  test "carga snapshots anteriores sin perder personas ni mensajes", %{
    ruta: ruta,
    inicial: inicial
  } do
    assert :ok = stop_supervised(EstadoServidor)
    {:ok, contenido} = File.read(ruta)
    datos = Jason.decode!(contenido)
    anterior = Map.update!(datos, "campos", &Map.delete(&1, "coincidencias_mascotas_por_id"))
    assert :ok = File.write(ruta, Jason.encode!(anterior))
    assert {:ok, recuperado} = Persistencia.cargar(ruta)
    assert recuperado == inicial
    assert recuperado.coincidencias_mascotas_por_id == %{}
    start_supervised!({EstadoServidor, path: ruta})
    assert :sys.get_state(EstadoServidor).estado == inicial
  end

  test "un proceso nuevo recupera los estados y tipos del snapshot", %{ruta: ruta} do
    {perdida, encontrada} = pareja()
    assert {:ok, _} = confirmar("coord", perdida, encontrada)
    ejecutable = System.find_executable("elixir.bat") || System.find_executable("elixir")
    rutas = :code.get_path() |> Enum.flat_map(fn ruta -> ["-pa", List.to_string(ruta)] end)

    script = Path.join(Path.dirname(ruta), "validar_snapshot.exs")

    File.write!(script, """
    case Emergencias.Persistencia.cargar(hd(System.argv())) do
      {:ok, _estado} -> IO.puts("snapshot recuperado")
      error ->
        IO.inspect(error)
        System.halt(1)
    end
    """)

    try do
      {salida, estado} =
        System.cmd(ejecutable, ["--erl", "+S 2"] ++ rutas ++ [script, ruta],
          stderr_to_stdout: true
        )

      assert estado == 0, salida
      assert salida =~ "snapshot recuperado"
    after
      File.rm(script)
    end
  end
end
