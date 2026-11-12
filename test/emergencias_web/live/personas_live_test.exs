defmodule EmergenciasWeb.PersonasLiveTest do
  use EmergenciasWeb.ConnCase, async: false
  alias Emergencias.{API, Estado, EstadoServidor, Persistencia, Usuarios, Zona}

  @moduletag capture_log: true

  setup do
    ruta =
      Path.join(
        System.tmp_dir!(),
        "personas-web-#{System.unique_integer([:positive])}/estado.json"
      )

    password = Base.url_encode64(:crypto.strong_rand_bytes(24))

    {:ok, usuarios} =
      Usuarios.provisionar_administrador(%{}, %{
        username: "admin",
        nombre_completo: "Administración",
        password: password,
        zona_principal: "Z-01"
      })

    estado = %Estado{
      usuarios_por_username: usuarios,
      zonas_por_codigo: %{
        "Z-01" => %Zona{codigo: "Z-01", nombre: "Zona uno"},
        "Z-02" => %Zona{codigo: "Z-02", nombre: "Zona dos"}
      }
    }

    assert :ok = Persistencia.guardar(estado, ruta)
    start_supervised!({EstadoServidor, path: ruta})
    assert {:ok, admin} = API.conectar(%{username: "admin", password: password})

    assert {:ok, ana} =
             API.conectar(%{
               username: "ana",
               password: password,
               nombre_completo: "Ana",
               zona_principal: "Z-01"
             })

    assert {:ok, otro} =
             API.conectar(%{
               username: "otro",
               password: password,
               nombre_completo: "Otro",
               zona_principal: "Z-01"
             })

    assert {:ok, fuera} =
             API.conectar(%{
               username: "fuera",
               password: password,
               nombre_completo: "Fuera",
               zona_principal: "Z-02"
             })

    on_exit(fn ->
      File.rm(ruta)
      File.rmdir(Path.dirname(ruta))
    end)

    %{ruta: ruta, admin: admin, ana: ana, otro: otro, fuera: fuera}
  end

  defp datos(nombre \\ "Persona de prueba", documento \\ "123") do
    %{
      "nombre" => nombre,
      "documento_referencia" => documento,
      "edad" => "20",
      "zona_codigo" => "Z-01",
      "estado" => "reportada"
    }
  end

  defp abrir(conn, sesion) do
    conn |> init_test_session(%{"session_id" => sesion.session_id}) |> live("/personas")
  end

  test "sin sesión conserva el diseño y restringe el acceso", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/acceso"}}} = live(conn, "/personas")
  end

  test "rechaza una sesión inválida y no confía en roles de la cookie", %{conn: conn} do
    conn =
      init_test_session(conn, %{
        "session_id" => "invalida",
        "rol" => "administrador",
        "zona_principal" => "Z-01"
      })

    assert {:error, {:redirect, %{to: "/acceso"}}} = live(conn, "/personas")
  end

  test "consulta solo su identidad pública y rechaza sesiones cerradas", c do
    assert {:ok, usuario} = API.consultar(c.ana.session_id, :sesion_actual)
    assert usuario.username == "ana"
    assert usuario.rol == :ciudadano
    refute Map.has_key?(usuario, :password_hash)

    assert {:error, :consulta_no_reconocida} =
             API.consultar(c.ana.session_id, {:sesion_actual, "admin"})

    assert :ok = API.desconectar(c.ana.session_id)
    assert {:error, :sesion_invalida} = API.consultar(c.ana.session_id, :sesion_actual)
    assert {:error, :sesion_invalida} = API.consultar(nil, :sesion_actual)
  end

  test "registra una persona y muestra detalles sin perder el diseño", c do
    assert {:ok, vista, _html} = abrir(c.conn, c.ana)
    assert has_element?(vista, "#listado-personas", "No hay personas")
    html = vista |> form("#registrar-persona", persona: datos()) |> render_submit()
    assert html =~ "Persona registrada."
    assert has_element?(vista, "#listado-personas", "Persona de prueba")
    assert has_element?(vista, "#detalle-persona", "No hay cambios de estado registrados.")
    assert {:ok, [persona]} = API.consultar(c.ana.session_id, {:personas, %{}})
    assert has_element?(vista, "#persona-#{persona.id}", "Reportada")
    assert has_element?(vista, "input[name='persona[nombre]'][value='']")
  end

  test "buscar por documento y filtrar usa datos autorizados", c do
    assert {:ok, primera} =
             API.ejecutar(c.ana.session_id, {:reportar_persona, datos("Primera", "111")})

    assert {:ok, segunda} =
             API.ejecutar(
               c.ana.session_id,
               {:reportar_persona, datos("Segunda", "222") |> Map.put("estado", "localizada")}
             )

    assert {:ok, _} =
             API.ejecutar(
               c.fuera.session_id,
               {:reportar_persona, datos("No visible", "111") |> Map.put("zona_codigo", "Z-02")}
             )

    assert {:ok, vista, _html} = abrir(c.conn, c.ana)
    vista |> form("#buscar-personas", busqueda: %{documento: "111"}) |> render_submit()
    assert has_element?(vista, "#persona-#{primera.id}")
    refute has_element?(vista, "#persona-#{segunda.id}")
    refute render(vista) =~ "No visible"

    vista
    |> form("#filtrar-personas", filtros: %{estado: "localizada", zona_codigo: ""})
    |> render_submit()

    assert has_element?(vista, "#persona-#{segunda.id}")
    refute has_element?(vista, "#persona-#{primera.id}")
    vista |> element("button", "Mostrar todas") |> render_click()
    assert has_element?(vista, "#persona-#{primera.id}")
  end

  test "el autor cambia estado y consulta historial; reunificada es final", c do
    assert {:ok, persona} = API.ejecutar(c.ana.session_id, {:reportar_persona, datos()})
    assert {:ok, vista, _html} = abrir(c.conn, c.ana)
    vista |> element("#persona-#{persona.id} button") |> render_click()
    vista |> form("#cambiar-estado-persona", cambio: %{estado: "localizada"}) |> render_submit()
    assert has_element?(vista, "[role=status]", "Estado actualizado")
    assert has_element?(vista, "#historial-persona", "Reportada → Localizada")
    assert has_element?(vista, "#historial-persona", "Usuario: ana")
    assert has_element?(vista, "#persona-#{persona.id}", "Localizada")
    vista |> form("#cambiar-estado-persona", cambio: %{estado: "reunificada"}) |> render_submit()
    assert has_element?(vista, "#detalle-persona", "estado final")
    refute has_element?(vista, "#cambiar-estado-persona")
    assert {:ok, [_, _]} = API.consultar(c.ana.session_id, {:historial_persona, persona.id})
  end

  test "rechaza cambios sin autoría, conserva selección y no expone otras zonas", c do
    assert {:ok, persona} = API.ejecutar(c.ana.session_id, {:reportar_persona, datos()})

    assert {:ok, fuera} =
             API.ejecutar(
               c.fuera.session_id,
               {:reportar_persona, datos("Otra zona") |> Map.put("zona_codigo", "Z-02")}
             )

    assert {:ok, vista, _html} = abrir(c.conn, c.otro)
    vista |> element("#persona-#{persona.id} button") |> render_click()
    vista |> form("#cambiar-estado-persona", cambio: %{estado: "localizada"}) |> render_submit()
    assert has_element?(vista, "[role=alert]", "no permite la operación")

    assert has_element?(
             vista,
             "select[name='cambio[estado]'] option[value='localizada'][selected]"
           )

    assert {:ok, %{estado: :reportada}} = API.consultar(c.ana.session_id, {:persona, persona.id})
    render_click(vista, "detalle", %{"id" => fuera.id})
    assert has_element?(vista, "[role=alert]", "no está disponible para esta sesión")
    refute has_element?(vista, "#detalle-persona")
    refute render(vista) =~ "Otra zona"
  end

  test "un administrador puede cambiar estados dentro del alcance global", c do
    assert {:ok, persona} =
             API.ejecutar(
               c.fuera.session_id,
               {:reportar_persona, datos() |> Map.put("zona_codigo", "Z-02")}
             )

    assert {:ok, vista, _html} = abrir(c.conn, c.admin)
    vista |> element("#persona-#{persona.id} button") |> render_click()
    vista |> form("#cambiar-estado-persona", cambio: %{estado: "trasladada"}) |> render_submit()
    assert has_element?(vista, "#historial-persona", "Usuario: admin")
  end

  test "un error de validación conserva los datos del formulario", c do
    assert {:ok, vista, _html} = abrir(c.conn, c.ana)
    attrs = datos("Conservar nombre") |> Map.put("edad", "-1")
    vista |> form("#registrar-persona", persona: attrs) |> render_submit()
    assert has_element?(vista, "[role=alert]", "edad debe ser")
    assert has_element?(vista, "input[name='persona[nombre]'][value='Conservar nombre']")
    assert has_element?(vista, "input[name='persona[edad]'][value='-1']")

    assert has_element?(
             vista,
             "select[name='persona[zona_codigo]'] option[value='Z-01'][selected]"
           )

    assert {:ok, []} = API.consultar(c.ana.session_id, {:personas, %{}})
  end

  test "una sesión cerrada limpia los datos mostrados y oculta los formularios", c do
    assert {:ok, _} = API.ejecutar(c.ana.session_id, {:reportar_persona, datos("Dato reservado")})
    assert {:ok, vista, _html} = abrir(c.conn, c.ana)
    assert :ok = API.desconectar(c.ana.session_id)
    vista |> element("button", "Mostrar todas") |> render_click()
    assert has_element?(vista, "#acceso-restringido")
    refute render(vista) =~ "Dato reservado"
    refute has_element?(vista, "#registrar-persona")
  end

  test "coordinador no disponible se distingue de un listado vacío", c do
    assert {:ok, vista, _html} = abrir(c.conn, c.ana)
    assert :ok = stop_supervised(EstadoServidor)
    vista |> element("button", "Mostrar todas") |> render_click()
    assert has_element?(vista, "[role=alert]", "coordinador no está disponible")
    assert has_element?(vista, "#listado-personas", "No se pudo cargar")
    refute has_element?(vista, "#listado-personas", "No hay personas")
  end

  test "el menú del panel conserva sus enlaces e incorpora personas", c do
    conn = init_test_session(c.conn, %{"session_id" => c.ana.session_id})
    assert {:ok, vista, _html} = live(conn, "/usuarios")
    assert has_element?(vista, "nav a[href='/personas']", "Personas")
    assert has_element?(vista, "nav a[href='/usuarios']", "Usuarios")

    vista
    |> element("nav a[href='/personas']")
    |> render_click()
    |> follow_redirect(conn, "/personas")
  end

  test "un voluntario cambia un reporte ajeno con autorización del backend", c do
    assert {:ok, _usuario} = API.ejecutar(c.admin.session_id, {:asignar_rol, "otro", :voluntario})
    assert {:ok, persona} = API.ejecutar(c.ana.session_id, {:reportar_persona, datos()})
    assert {:ok, vista, _html} = abrir(c.conn, c.otro)
    vista |> element("#persona-#{persona.id} button") |> render_click()
    vista |> form("#cambiar-estado-persona", cambio: %{estado: "en_albergue"}) |> render_submit()
    assert has_element?(vista, "#historial-persona", "Reportada → En albergue")
    assert has_element?(vista, "#historial-persona", "Usuario: otro")
  end

  test "un error de escritura conserva el formulario y los registros anteriores", c do
    assert {:ok, vista, _html} = abrir(c.conn, c.ana)
    :sys.replace_state(EstadoServidor, &%{&1 | ruta: Path.join(c.ruta, "imposible.json")})
    vista |> form("#registrar-persona", persona: datos("Conservar tras fallo")) |> render_submit()
    assert has_element?(vista, "[role=alert]", "No se pudo guardar")
    assert has_element?(vista, "input[name='persona[nombre]'][value='Conservar tras fallo']")
    assert has_element?(vista, "input[name='persona[documento_referencia]'][value='123']")
    assert {:ok, []} = API.consultar(c.ana.session_id, {:personas, %{}})
  end
end
