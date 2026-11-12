defmodule EmergenciasWeb.MascotasLiveTest do
  use EmergenciasWeb.ConnCase, async: false
  alias Emergencias.{API, Estado, EstadoServidor, Persistencia, Usuarios, Zona}
  @moduletag capture_log: true

  setup do
    ruta =
      Path.join(
        System.tmp_dir!(),
        "mascotas-web-#{System.unique_integer([:positive])}/estado.json"
      )

    password = Base.url_encode64(:crypto.strong_rand_bytes(24))

    {:ok, usuarios} =
      Usuarios.provisionar_administrador(%{}, %{
        username: "admin",
        nombre_completo: "Administración",
        password: password,
        zona_principal: "Z1"
      })

    estado = %Estado{
      usuarios_por_username: usuarios,
      zonas_por_codigo: %{
        "Z1" => %Zona{codigo: "Z1", nombre: "Zona uno"},
        "Z2" => %Zona{codigo: "Z2", nombre: "Zona dos"}
      }
    }

    assert :ok = Persistencia.guardar(estado, ruta)
    start_supervised!({EstadoServidor, path: ruta})
    assert {:ok, admin} = API.conectar(%{username: "admin", password: password})

    sesiones =
      Map.new(
        [
          {"ana", "Z1", :ciudadano},
          {"vol", "Z1", :voluntario},
          {"coord", "Z1", :coordinador},
          {"fuera", "Z2", :coordinador}
        ],
        fn {nombre, zona, rol} ->
          assert {:ok, sesion} =
                   API.conectar(%{
                     username: nombre,
                     password: password,
                     nombre_completo: String.capitalize(nombre),
                     zona_principal: zona
                   })

          if rol != :ciudadano do
            assert {:ok, _usuario} = API.ejecutar(admin.session_id, {:asignar_rol, nombre, rol})
          end

          {nombre, sesion}
        end
      )

    on_exit(fn ->
      File.rm(ruta)
      File.rmdir(Path.dirname(ruta))
    end)

    %{
      ruta: ruta,
      admin: admin,
      ana: sesiones["ana"],
      vol: sesiones["vol"],
      coord: sesiones["coord"],
      fuera: sesiones["fuera"]
    }
  end

  defp datos(tipo \\ "perdida", zona \\ "Z1") do
    %{
      "tipo_reporte" => tipo,
      "especie" => "perro",
      "nombre" => "Luna",
      "color" => "negro",
      "tamano" => "mediano",
      "caracteristicas" => "mancha blanca",
      "zona_codigo" => zona,
      "contacto" => "Familia del reporte"
    }
  end

  defp registrar(sesion, tipo \\ "perdida", zona \\ "Z1"),
    do: API.ejecutar(sesion.session_id, {:reportar_mascota, datos(tipo, zona)})

  defp pareja(c) do
    assert {:ok, perdida} = registrar(c.ana)
    assert {:ok, encontrada} = registrar(c.ana, "encontrada")
    {perdida, encontrada}
  end

  defp abrir(conn, sesion),
    do: conn |> init_test_session(%{"session_id" => sesion.session_id}) |> live("/mascotas")

  defp buscar(vista, reporte),
    do:
      vista
      |> element("#reporte-#{reporte.id} button[phx-click='buscar_coincidencias']")
      |> render_click()

  defp revisar(vista, candidato),
    do:
      vista |> element("#candidato-#{candidato.id} button[phx-click='revisar']") |> render_click()

  test "sin sesión conserva el diseño claro y restringe el acceso", c do
    assert {:ok, vista, html} = live(c.conn, "/mascotas")
    assert html =~ "Mascotas perdidas y encontradas"
    assert html =~ "Registro y búsqueda de mascotas con identificación de posibles coincidencias."
    assert html =~ "MÓDULO DE MARIA FERNANDA MEJÍA OCAMPO"
    assert html =~ "min-h-screen bg-slate-50 text-slate-900"
    assert html =~ "bg-slate-950 text-white"
    assert html =~ "rounded-xl border border-slate-200 bg-white p-6 shadow-sm"
    assert html =~ "Proyecto final · Programación III"
    assert has_element?(vista, "nav a[href='/mascotas'][aria-current='page']")
    assert has_element?(vista, "#acceso-restringido", "sesión activa")
    refute has_element?(vista, "#registrar-mascota")
    refute has_element?(vista, "#listado-mascotas")
  end

  test "rechaza sesiones inválidas sin aceptar roles de la cookie", c do
    conn = init_test_session(c.conn, %{"session_id" => "invalida", "rol" => "administrador"})
    assert {:ok, vista, _html} = live(conn, "/mascotas")
    assert has_element?(vista, "#acceso-restringido")
    assert has_element?(vista, "[role=alert]", "sesión no es válida")
    refute has_element?(vista, "#registrar-mascota")
  end

  test "registra pérdida y hallazgo y muestra sus detalles", c do
    assert {:ok, vista, _html} = abrir(c.conn, c.ana)

    for tipo <- ["perdida", "encontrada"] do
      vista |> form("#registrar-mascota", mascota: datos(tipo)) |> render_submit()
      assert has_element?(vista, "[role=status]", "Reporte de mascota registrado")
      assert has_element?(vista, "#detalle-mascota", "Familia del reporte")
      assert has_element?(vista, "#detalle-mascota", "Activa")
    end

    assert {:ok, reportes} = API.consultar(c.ana.session_id, {:reportes_mascotas, %{}})
    assert length(reportes) == 2

    for reporte <- reportes do
      assert has_element?(vista, "#reporte-#{reporte.id}", "Luna")
    end

    assert has_element?(vista, "input[name='mascota[nombre]'][value='']")
  end

  test "combina filtros por tipo, especie, zona y estado", c do
    {perdida, encontrada} = pareja(c)
    assert {:ok, vista, _html} = abrir(c.conn, c.ana)
    filtros = %{tipo_reporte: "encontrada", especie: "PERRO", zona_codigo: "Z1", estado: "activa"}
    vista |> form("#filtrar-mascotas", filtros: filtros) |> render_submit()
    assert has_element?(vista, "#reporte-#{encontrada.id}")
    refute has_element?(vista, "#reporte-#{perdida.id}")
    vista |> element("#reporte-#{encontrada.id} button[phx-click='detalle']") |> render_click()
    assert has_element?(vista, "#detalle-mascota", encontrada.id)
    vista |> element("button", "Mostrar todos") |> render_click()
    assert has_element?(vista, "#reporte-#{perdida.id}")
  end

  test "muestra exactamente puntaje y desglose de API sin mutar reportes", c do
    {perdida, encontrada} = pareja(c)

    assert {:ok, [resultado]} =
             API.consultar(c.ana.session_id, {:posibles_coincidencias_mascota, perdida.id})

    assert {:ok, vista, _html} = abrir(c.conn, c.ana)
    buscar(vista, perdida)

    assert has_element?(
             vista,
             "#candidato-#{encontrada.id}",
             "Similitud: #{resultado.puntaje} / 100 puntos"
           )

    for {campo, maximo} <- [
          especie: 30,
          color: 20,
          tamano: 15,
          caracteristicas: 20,
          zona_codigo: 10,
          nombre: 5
        ] do
      assert has_element?(
               vista,
               "#candidato-#{encontrada.id} dd",
               "#{resultado.desglose[campo]} / #{maximo}"
             )
    end

    assert has_element?(vista, "#posibles-coincidencias", "no es una probabilidad")
    refute has_element?(vista, "button[phx-click='proponer']")
    refute has_element?(vista, "button[phx-click='revisar']")

    assert {:ok, %{estado: :activa}} =
             API.consultar(c.ana.session_id, {:reporte_mascota, perdida.id})

    assert {:ok, []} = API.consultar(c.ana.session_id, {:coincidencias_mascotas, %{}})
  end

  test "un voluntario propone y ambos reportes permanecen abiertos", c do
    {perdida, encontrada} = pareja(c)
    assert {:ok, vista, _html} = abrir(c.conn, c.vol)
    buscar(vista, perdida)
    vista |> element("#candidato-#{encontrada.id} button[phx-click='proponer']") |> render_click()
    assert has_element?(vista, "[role=status]", "Coincidencia propuesta")
    assert has_element?(vista, "#reporte-#{perdida.id}", "Posible coincidencia")
    assert has_element?(vista, "#reporte-#{encontrada.id}", "Posible coincidencia")
    assert has_element?(vista, "#coincidencias-registradas", "Propuesta")
    refute has_element?(vista, "#confirmar-coincidencia")
    vista |> element("#candidato-#{encontrada.id} button[phx-click='proponer']") |> render_click()
    assert has_element?(vista, "[role=alert]", "ya tiene una propuesta")
  end

  test "confirmar exige revisión y una segunda acción explícita", c do
    {perdida, encontrada} = pareja(c)
    assert {:ok, vista, _html} = abrir(c.conn, c.coord)
    render_click(vista, "confirmar", %{"perdida" => perdida.id, "encontrada" => encontrada.id})
    assert has_element?(vista, "[role=alert]", "Revisa primero")
    assert {:ok, []} = API.consultar(c.coord.session_id, {:coincidencias_mascotas, %{}})
    buscar(vista, perdida)
    revisar(vista, encontrada)
    assert has_element?(vista, "#revision-coincidencia", perdida.id)
    assert has_element?(vista, "#revision-coincidencia", encontrada.id)
    assert has_element?(vista, "#confirmar-coincidencia[data-confirm]")

    assert {:ok, %{estado: :activa}} =
             API.consultar(c.coord.session_id, {:reporte_mascota, perdida.id})

    vista |> element("#confirmar-coincidencia") |> render_click()
    assert has_element?(vista, "[role=status]", "Ambos reportes fueron resueltos")

    for reporte <- [perdida, encontrada] do
      assert has_element?(vista, "#reporte-#{reporte.id}", "Resuelta")

      refute has_element?(
               vista,
               "#reporte-#{reporte.id} button[phx-click='buscar_coincidencias']"
             )
    end

    assert has_element?(vista, "#coincidencias-registradas", "Confirmada por: coord")
    refute has_element?(vista, "#revision-coincidencia")
  end

  test "cancelar revisión no modifica los reportes y la búsqueda funciona desde hallazgo", c do
    {perdida, encontrada} = pareja(c)
    assert {:ok, vista, _html} = abrir(c.conn, c.coord)
    buscar(vista, encontrada)
    revisar(vista, perdida)
    assert has_element?(vista, "#revision-coincidencia", perdida.id)
    vista |> element("button[phx-click='cancelar_revision']") |> render_click()
    refute has_element?(vista, "#revision-coincidencia")
    assert {:ok, []} = API.consultar(c.coord.session_id, {:coincidencias_mascotas, %{}})
  end

  test "revisa una propuesta registrada antes de confirmarla", c do
    {perdida, encontrada} = pareja(c)

    assert {:ok, propuesta} =
             API.ejecutar(
               c.vol.session_id,
               {:proponer_coincidencia_mascota, perdida.id, encontrada.id}
             )

    assert {:ok, vista, _html} = abrir(c.conn, c.coord)
    vista |> element("#coincidencia-#{propuesta.id} button") |> render_click()
    assert has_element?(vista, "#revision-coincidencia", "Revisar antes de confirmar")
    vista |> element("#confirmar-coincidencia") |> render_click()
    assert has_element?(vista, "#coincidencia-#{propuesta.id}", "Confirmada")
  end

  test "el backend rechaza propuestas ciudadanas y cierres de ciudadano o voluntario", c do
    {perdida, encontrada} = pareja(c)
    assert {:ok, ciudadana, _html} = abrir(c.conn, c.ana)
    ids = %{"perdida" => perdida.id, "encontrada" => encontrada.id}
    render_click(ciudadana, "proponer", ids)
    assert has_element?(ciudadana, "[role=alert]", "Tu rol o zona no permite")

    for sesion <- [c.ana, c.vol] do
      assert {:ok, vista, _html} = abrir(c.conn, sesion)
      render_click(vista, "revisar", ids)
      refute has_element?(vista, "#confirmar-coincidencia")
      render_click(vista, "confirmar", %{"rol" => "administrador"})
      assert has_element?(vista, "[role=alert]", "Tu rol o zona no permite")
    end

    assert {:ok, []} = API.consultar(c.coord.session_id, {:coincidencias_mascotas, %{}})
  end

  test "restringe zonas aun con eventos manipulados y permite confirmación global autorizada",
       c do
    assert {:ok, perdida} = registrar(c.ana)
    assert {:ok, encontrada} = registrar(c.fuera, "encontrada", "Z2")
    assert {:ok, vista, _html} = abrir(c.conn, c.coord)
    refute has_element?(vista, "#reporte-#{encontrada.id}")
    render_click(vista, "revisar", %{"perdida" => perdida.id, "encontrada" => encontrada.id})
    assert has_element?(vista, "[role=alert]", "no está disponible para esta sesión")
    refute has_element?(vista, "#revision-coincidencia")
    render_click(vista, "proponer", %{"perdida" => perdida.id, "encontrada" => encontrada.id})
    assert has_element?(vista, "[role=alert]", "no está disponible para esta sesión")
    assert {:ok, admin_vista, _html} = abrir(c.conn, c.admin)
    buscar(admin_vista, perdida)
    revisar(admin_vista, encontrada)
    admin_vista |> element("#confirmar-coincidencia") |> render_click()
    assert has_element?(admin_vista, "#reporte-#{encontrada.id}", "Resuelta")
    assert has_element?(admin_vista, "#reporte-#{perdida.id}", "Resuelta")
  end

  test "la pareja revisada no puede sustituirse con parámetros al confirmar", c do
    {perdida, encontrada} = pareja(c)
    assert {:ok, otra} = registrar(c.ana, "encontrada")
    assert {:ok, vista, _html} = abrir(c.conn, c.coord)
    buscar(vista, perdida)
    revisar(vista, encontrada)
    render_click(vista, "confirmar", %{"perdida" => perdida.id, "encontrada" => otra.id})
    assert {:ok, [confirmada]} = API.consultar(c.coord.session_id, {:coincidencias_mascotas, %{}})
    assert confirmada.reporte_encontrada_id == encontrada.id

    assert {:ok, %{estado: :activa}} =
             API.consultar(c.coord.session_id, {:reporte_mascota, otra.id})
  end

  test "si otra sesión resuelve una pareja, se rechaza el cierre y se actualizan los estados",
       c do
    {perdida, encontrada} = pareja(c)
    assert {:ok, otra} = registrar(c.ana, "encontrada")
    assert {:ok, vista, _html} = abrir(c.conn, c.coord)
    buscar(vista, perdida)
    revisar(vista, encontrada)

    assert {:ok, _} =
             API.ejecutar(
               c.admin.session_id,
               {:confirmar_coincidencia_mascota, perdida.id, otra.id}
             )

    vista |> element("#confirmar-coincidencia") |> render_click()
    assert has_element?(vista, "[role=alert]", "ya está resuelto")
    refute has_element?(vista, "#revision-coincidencia")
    assert has_element?(vista, "#reporte-#{perdida.id}", "Resuelta")
    assert has_element?(vista, "#reporte-#{encontrada.id}", "Activa")
  end

  test "sin candidatos compatibles muestra estado vacío y rechaza revisar una pareja incompatible",
       c do
    assert {:ok, perdida} = registrar(c.ana)

    assert {:ok, gato} =
             API.ejecutar(
               c.ana.session_id,
               {:reportar_mascota, datos("encontrada") |> Map.put("especie", "gato")}
             )

    assert {:ok, vista, _html} = abrir(c.conn, c.coord)
    buscar(vista, perdida)
    assert has_element?(vista, "#posibles-coincidencias", "No hay reportes compatibles")
    render_click(vista, "revisar", %{"perdida" => perdida.id, "encontrada" => gato.id})
    assert has_element?(vista, "[role=alert]", "compatibilidad de especie")
    refute has_element?(vista, "#revision-coincidencia")
  end

  test "validaciones y fallas de escritura conservan los formularios", c do
    assert {:ok, vista, _html} = abrir(c.conn, c.ana)
    attrs = datos() |> Map.put("contacto", " ")
    vista |> form("#registrar-mascota", mascota: attrs) |> render_submit()
    assert has_element?(vista, "[role=alert]", "campos obligatorios")
    assert has_element?(vista, "input[name='mascota[nombre]'][value='Luna']")
    assert has_element?(vista, "textarea[name='mascota[caracteristicas]']", "mancha blanca")
    :sys.replace_state(EstadoServidor, &%{&1 | ruta: Path.join(c.ruta, "imposible.json")})
    vista |> form("#registrar-mascota", mascota: datos()) |> render_submit()
    assert has_element?(vista, "[role=alert]", "No se pudo guardar")
    assert has_element?(vista, "input[name='mascota[contacto]'][value='Familia del reporte']")
    assert {:ok, []} = API.consultar(c.ana.session_id, {:reportes_mascotas, %{}})
  end

  test "un error al persistir la confirmación conserva ambos reportes abiertos", c do
    {perdida, encontrada} = pareja(c)
    assert {:ok, vista, _html} = abrir(c.conn, c.coord)
    buscar(vista, perdida)
    revisar(vista, encontrada)
    :sys.replace_state(EstadoServidor, &%{&1 | ruta: Path.join(c.ruta, "imposible.json")})
    vista |> element("#confirmar-coincidencia") |> render_click()
    assert has_element?(vista, "[role=alert]", "No se pudo guardar")
    refute has_element?(vista, "#cierre-coincidencia")

    for reporte <- [perdida, encontrada] do
      assert {:ok, %{estado: :activa}} =
               API.consultar(c.coord.session_id, {:reporte_mascota, reporte.id})
    end
  end

  test "sesión cerrada limpia datos, búsqueda y revisión", c do
    {perdida, encontrada} = pareja(c)
    assert {:ok, vista, _html} = abrir(c.conn, c.coord)
    buscar(vista, perdida)
    revisar(vista, encontrada)
    assert :ok = API.desconectar(c.coord.session_id)
    vista |> element("#confirmar-coincidencia") |> render_click()
    assert has_element?(vista, "#acceso-restringido")
    refute has_element?(vista, "#revision-coincidencia")
    refute render(vista) =~ "Familia del reporte"
  end

  test "errores de carga se distinguen de listas vacías", c do
    assert {:ok, vista, _html} = abrir(c.conn, c.ana)
    render_submit(vista, "filtrar", %{"filtros" => Map.put(datos(), "estado", "invalido")})
    assert has_element?(vista, "[role=alert]", "estado válido")
    assert has_element?(vista, "#listado-mascotas", "No se pudieron cargar")
    refute has_element?(vista, "#listado-mascotas", "No hay reportes")
    assert :ok = stop_supervised(EstadoServidor)
    vista |> element("button", "Mostrar todos") |> render_click()
    assert has_element?(vista, "[role=alert]", "coordinador no está disponible")
  end

  test "menú conserva enlaces e incorpora mascotas en todas las vistas de Mafe", c do
    for ruta <- ["/usuarios", "/personas", "/mensajes"] do
      conn = init_test_session(c.conn, %{"session_id" => c.ana.session_id})
      assert {:ok, vista, _html} = live(conn, ruta)
      assert has_element?(vista, "nav a[href='/mascotas']", "Mascotas")
    end

    assert {:ok, vista, _html} = abrir(c.conn, c.ana)

    for ruta <- ["/", "/usuarios", "/zonas", "/albergues", "/personas", "/mensajes"] do
      assert has_element?(vista, "nav a[href='#{ruta}']")
    end
  end
end
