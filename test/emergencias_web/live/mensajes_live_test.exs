defmodule EmergenciasWeb.MensajesLiveTest do
  use EmergenciasWeb.ConnCase, async: false
  alias Emergencias.{API, Estado, EstadoServidor, Persistencia, Usuarios, Zona}
  @moduletag capture_log: true

  setup do
    ruta =
      Path.join(
        System.tmp_dir!(),
        "mensajes-web-#{System.unique_integer([:positive])}/estado.json"
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

    sesiones =
      Map.new([{"ana", "Z-01"}, {"otro", "Z-01"}, {"fuera", "Z-02"}], fn {nombre, zona} ->
        {:ok, sesion} =
          API.conectar(%{
            username: nombre,
            password: password,
            nombre_completo: String.capitalize(nombre),
            zona_principal: zona
          })

        {nombre, sesion}
      end)

    assert {:ok, primera} =
             API.ejecutar(
               sesiones["ana"].session_id,
               {:reportar_persona, %{nombre: "Primera persona", edad: 20, zona_codigo: "Z-01"}}
             )

    assert {:ok, segunda} =
             API.ejecutar(
               sesiones["ana"].session_id,
               {:reportar_persona, %{nombre: "Segunda persona", edad: 30, zona_codigo: "Z-01"}}
             )

    assert {:ok, exterior} =
             API.ejecutar(
               sesiones["fuera"].session_id,
               {:reportar_persona, %{nombre: "Persona exterior", edad: 40, zona_codigo: "Z-02"}}
             )

    on_exit(fn ->
      File.rm(ruta)
      File.rmdir(Path.dirname(ruta))
    end)

    %{
      ruta: ruta,
      admin: admin,
      ana: sesiones["ana"],
      otro: sesiones["otro"],
      fuera: sesiones["fuera"],
      primera: primera,
      segunda: segunda,
      exterior: exterior
    }
  end

  defp datos(persona, contenido \\ "Estamos bien") do
    %{
      "persona_id" => persona.id,
      "remitente" => "Otro",
      "destinatario" => "Otro",
      "contenido" => contenido
    }
  end

  defp crear(sesion, persona, contenido \\ "Estamos bien") do
    API.ejecutar(
      sesion.session_id,
      {:enviar_mensaje_familiar, persona.id, datos(persona, contenido)}
    )
  end

  defp abrir(conn, sesion),
    do: conn |> init_test_session(%{"session_id" => sesion.session_id}) |> live("/mensajes")

  test "sin sesión presenta el diseño claro y acceso restringido", c do
    assert {:error, {:redirect, %{to: "/acceso"}}} = live(c.conn, "/mensajes")
  end

  test "sesión inválida no puede habilitarse mediante rol en la cookie", c do
    conn = init_test_session(c.conn, %{"session_id" => "invalida", "rol" => "administrador"})
    assert {:error, {:redirect, %{to: "/acceso"}}} = live(conn, "/mensajes")
  end

  test "crea mensajes pendientes y muestra la información devuelta", c do
    assert {:ok, vista, _html} = abrir(c.conn, c.ana)
    assert has_element?(vista, "#listado-mensajes", "No hay mensajes")
    vista |> form("#crear-mensaje", mensaje: datos(c.primera, "Hola familia")) |> render_submit()
    assert has_element?(vista, "[role=status]", "Mensaje creado como pendiente")
    assert {:ok, [mensaje]} = API.consultar(c.ana.session_id, {:mensajes_familiares, %{}})
    assert has_element?(vista, "#mensaje-#{mensaje.id}", "Hola familia")
    assert has_element?(vista, "#mensaje-#{mensaje.id}", "Primera persona")
    assert has_element?(vista, "#mensaje-#{mensaje.id}", "Pendiente")
    assert has_element?(vista, "#mensaje-#{mensaje.id}", "Otro")
    assert has_element?(vista, "input[name='mensaje[remitente]'][value='']")
    refute has_element?(vista, "button[phx-click='entregar']")
  end

  test "filtra por persona y estado y permite limpiar filtros", c do
    assert {:ok, primero} = crear(c.ana, c.primera, "Mensaje uno")
    assert {:ok, segundo} = crear(c.ana, c.segunda, "Mensaje dos")
    assert {:ok, _} = API.ejecutar(c.admin.session_id, {:marcar_mensaje_entregado, segundo.id})
    assert {:ok, vista, _html} = abrir(c.conn, c.ana)

    vista
    |> form("#filtrar-mensajes", filtros: %{persona_id: c.primera.id, estado: "pendiente"})
    |> render_submit()

    assert has_element?(vista, "#mensaje-#{primero.id}")
    refute has_element?(vista, "#mensaje-#{segundo.id}")

    vista
    |> form("#filtrar-mensajes", filtros: %{persona_id: c.segunda.id, estado: "entregado"})
    |> render_submit()

    assert has_element?(vista, "#mensaje-#{segundo.id}", "Entregado")
    refute has_element?(vista, "#mensaje-#{primero.id}")
    vista |> element("button", "Mostrar todos") |> render_click()
    assert has_element?(vista, "#mensaje-#{primero.id}")
    assert has_element?(vista, "#mensaje-#{segundo.id}")
  end

  test "el voluntario autorizado confirma la entrega", c do
    assert {:ok, _} = API.ejecutar(c.admin.session_id, {:asignar_rol, "otro", :voluntario})
    assert {:ok, mensaje} = crear(c.ana, c.primera)
    assert {:ok, vista, _html} = abrir(c.conn, c.otro)
    assert has_element?(vista, "#mensaje-#{mensaje.id} button[data-confirm]")
    vista |> element("#mensaje-#{mensaje.id} button") |> render_click()
    assert has_element?(vista, "[role=status]", "Entrega del mensaje confirmada")
    assert has_element?(vista, "#mensaje-#{mensaje.id}", "Entregado")
    refute has_element?(vista, "#mensaje-#{mensaje.id} button")

    assert {:ok, [%{estado: :entregado}]} =
             API.consultar(c.ana.session_id, {:mensajes_familiares, %{}})

    render_click(vista, "entregar", %{"id" => mensaje.id})
    assert has_element?(vista, "[role=alert]", "ya fue entregado")
  end

  test "el coordinador también confirma entregas", c do
    assert {:ok, _} = API.ejecutar(c.admin.session_id, {:asignar_rol, "otro", :coordinador})
    assert {:ok, mensaje} = crear(c.ana, c.primera)
    assert {:ok, vista, _html} = abrir(c.conn, c.otro)
    vista |> element("#mensaje-#{mensaje.id} button") |> render_click()
    assert has_element?(vista, "#mensaje-#{mensaje.id}", "Entregado")
  end

  test "ciudadanos no entregan ni siquiera enviando un evento directo", c do
    assert {:ok, mensaje} = crear(c.ana, c.primera)
    assert {:ok, vista, _html} = abrir(c.conn, c.ana)
    refute has_element?(vista, "button[phx-click='entregar']")
    render_click(vista, "entregar", %{"id" => mensaje.id, "rol" => "administrador"})
    assert has_element?(vista, "[role=alert]", "no permite gestionar")

    assert {:ok, [%{estado: :pendiente}]} =
             API.consultar(c.ana.session_id, {:mensajes_familiares, %{}})
  end

  test "remitente y destinatario no conceden acceso a los mensajes de otro autor", c do
    assert {:ok, ajeno} = crear(c.ana, c.primera, "Contenido ajeno")
    assert {:ok, propio} = crear(c.otro, c.segunda, "Contenido propio")
    assert {:ok, vista, _html} = abrir(c.conn, c.otro)
    refute has_element?(vista, "#mensaje-#{ajeno.id}")
    assert has_element?(vista, "#mensaje-#{propio.id}")

    vista
    |> form("#filtrar-mensajes", filtros: %{persona_id: c.primera.id, estado: ""})
    |> render_submit()

    assert has_element?(vista, "#listado-mensajes", "No hay mensajes")
    refute render(vista) =~ "Contenido ajeno"
  end

  test "restringe zonas incluso con eventos manipulados y permite administración global", c do
    assert {:ok, exterior} = crear(c.fuera, c.exterior, "Contenido de otra zona")
    assert {:ok, _} = API.ejecutar(c.admin.session_id, {:asignar_rol, "otro", :voluntario})
    assert {:ok, vista, _html} = abrir(c.conn, c.otro)
    refute render(vista) =~ "Persona exterior"
    render_click(vista, "entregar", %{"id" => exterior.id})
    assert has_element?(vista, "[role=alert]", "no está disponible")
    render_submit(vista, "crear", %{"mensaje" => datos(c.exterior)})
    assert has_element?(vista, "[role=alert]", "no está disponible")

    render_submit(vista, "filtrar", %{
      "filtros" => %{"persona_id" => c.exterior.id, "estado" => ""}
    })

    refute render(vista) =~ "Contenido de otra zona"
    assert {:ok, admin_vista, _html} = abrir(c.conn, c.admin)
    assert has_element?(admin_vista, "#mensaje-#{exterior.id}")
    admin_vista |> element("#mensaje-#{exterior.id} button") |> render_click()
    assert has_element?(admin_vista, "#mensaje-#{exterior.id}", "Entregado")
  end

  test "fallar una validación conserva campos y selección", c do
    assert {:ok, vista, _html} = abrir(c.conn, c.ana)
    attrs = datos(c.primera) |> Map.put("remitente", " ")
    vista |> form("#crear-mensaje", mensaje: attrs) |> render_submit()
    assert has_element?(vista, "[role=alert]", "campos obligatorios")

    assert has_element?(
             vista,
             "select[name='mensaje[persona_id]'] option[value='#{c.primera.id}'][selected]"
           )

    assert has_element?(vista, "input[name='mensaje[destinatario]'][value='Otro']")
    assert has_element?(vista, "textarea[name='mensaje[contenido]']", "Estamos bien")
    assert {:ok, []} = API.consultar(c.ana.session_id, {:mensajes_familiares, %{}})
  end

  test "fallar una escritura conserva el formulario y un mensaje no entregado", c do
    assert {:ok, mensaje} = crear(c.ana, c.primera)
    assert {:ok, vista, _html} = abrir(c.conn, c.admin)
    :sys.replace_state(EstadoServidor, &%{&1 | ruta: Path.join(c.ruta, "imposible.json")})

    vista
    |> form("#crear-mensaje", mensaje: datos(c.segunda, "Conservar este contenido"))
    |> render_submit()

    assert has_element?(vista, "[role=alert]", "No se pudo guardar")
    assert has_element?(vista, "textarea[name='mensaje[contenido]']", "Conservar este contenido")
    vista |> element("#mensaje-#{mensaje.id} button") |> render_click()
    assert has_element?(vista, "[role=alert]", "No se pudo guardar")
    assert has_element?(vista, "#mensaje-#{mensaje.id}", "Pendiente")
  end

  test "cerrar la sesión elimina la información mostrada y restringe el acceso", c do
    assert {:ok, _} = crear(c.ana, c.primera, "Contenido reservado")
    assert {:ok, vista, _html} = abrir(c.conn, c.ana)
    assert :ok = API.desconectar(c.ana.session_id)
    vista |> element("button", "Mostrar todos") |> render_click()
    assert has_element?(vista, "#acceso-restringido")
    refute render(vista) =~ "Contenido reservado"
    refute has_element?(vista, "#crear-mensaje")
  end

  test "coordinador no disponible y filtros inválidos no parecen listados vacíos", c do
    assert {:ok, vista, _html} = abrir(c.conn, c.ana)
    render_submit(vista, "filtrar", %{"filtros" => %{"persona_id" => "", "estado" => "invalido"}})
    assert has_element?(vista, "[role=alert]", "estado válido")
    assert has_element?(vista, "#listado-mensajes", "No se pudo cargar")
    refute has_element?(vista, "#listado-mensajes", "No hay mensajes")
    assert :ok = stop_supervised(EstadoServidor)
    vista |> element("button", "Mostrar todos") |> render_click()
    assert has_element?(vista, "[role=alert]", "coordinador no está disponible")
    assert has_element?(vista, "#listado-mensajes", "No se pudo cargar")
  end

  test "la navegación conserva los módulos e incorpora mensajes", c do
    conn = init_test_session(c.conn, %{"session_id" => c.ana.session_id})
    assert {:ok, panel, _html} = live(conn, "/usuarios")
    assert has_element?(panel, "nav a[href='/mensajes']", "Mensajes")

    panel
    |> element("nav[aria-label='Navegación principal'] a[href='/mensajes']")
    |> render_click()
    |> follow_redirect(conn, "/mensajes")

    assert {:ok, personas, _html} = abrir_personas(c.conn, c.ana)
    assert has_element?(personas, "nav a[href='/mensajes']")
    assert {:ok, mensajes, _html} = abrir(c.conn, c.ana)

    for ruta <- ["/", "/usuarios", "/zonas", "/albergues", "/personas"] do
      assert has_element?(mensajes, "nav[aria-label='Módulos'] a[href='#{ruta}']")
    end
  end

  defp abrir_personas(conn, sesion),
    do: conn |> init_test_session(%{"session_id" => sesion.session_id}) |> live("/personas")
end
