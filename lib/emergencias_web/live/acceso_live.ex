defmodule EmergenciasWeb.AccesoLive do
  @moduledoc "Flujo de inicio de sesión y registro ciudadano."
  use EmergenciasWeb, :live_view

  alias Emergencias.API
  alias EmergenciasWeb.AppShell

  @impl true
  def mount(params, session, socket) do
    modo = if params["modo"] == "registro", do: :registro, else: :ingresar

    {:ok,
     assign(socket,
       csrf_token: session["csrf_token"],
       zonas:
         API.zonas_para_registro()
         |> opciones_zona(),
       modo: modo,
       mensaje: mensaje(params),
       tipo_mensaje: if(params["error"], do: "error", else: "info")
     )}
  end

  @impl true
  def handle_event("cambiar_modo", %{"modo" => modo}, socket) do
    modo = if modo == "registro", do: :registro, else: :ingresar
    {:noreply, assign(socket, modo: modo, mensaje: nil, tipo_mensaje: "info")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell title="Acceso" current_path="/acceso">
      <div class="mx-auto grid max-w-5xl gap-8 lg:grid-cols-[0.9fr_1.1fr] lg:items-center">
        <section class="rounded-3xl bg-slate-950 p-7 text-white sm:p-9">
          <span class="grid size-12 place-items-center rounded-2xl bg-orange-600 text-2xl font-black">E</span>
          <p class="mt-7 text-xs font-bold uppercase tracking-[0.2em] text-orange-400">
            Acceso al sistema
          </p>

          <h1 class="mt-3 text-3xl font-black">Bienvenido al centro de coordinación.</h1>

          <p class="mt-4 leading-7 text-slate-300">
            Inicia sesión o registra una cuenta ciudadana para continuar.
          </p>

          <div class="mt-7 rounded-xl border border-amber-300/20 bg-amber-300/10 p-4 text-sm leading-6 text-amber-100">
            El registro público asigna el rol ciudadano. Los permisos disponibles dependen del rol de cada cuenta.
          </div>
        </section>

        <section class="rounded-3xl border border-slate-200 bg-white p-6 shadow-sm sm:p-8">
          <div class="flex gap-2 rounded-xl bg-slate-100 p-1.5">
            <button
              type="button"
              phx-click="cambiar_modo"
              phx-value-modo="ingresar"
              class={tab_class(@modo == :ingresar)}
            >Iniciar sesión</button>
            <button
              type="button"
              phx-click="cambiar_modo"
              phx-value-modo="registro"
              class={tab_class(@modo == :registro)}
            >Crear cuenta</button>
          </div>

          <h2 class="mt-7 text-2xl font-bold">
            {if @modo == :registro, do: "Crea tu cuenta", else: "Ingresa a tu cuenta"}
          </h2>

          <p class="mt-2 text-sm text-slate-600">
            {if @modo == :registro,
              do: "El registro público crea cuentas con rol ciudadano.",
              else: "Ingresa tus credenciales para acceder."}
          </p>

          <form action="/sesion" method="post" class="mt-6 space-y-4">
            <input type="hidden" name="_csrf_token" value={@csrf_token} />
            <input
              type="hidden"
              name="usuario[modo]"
              value={if @modo == :registro, do: "registro", else: "ingresar"}
            />
            <AppShell.field
              label="Nombre de usuario"
              name="usuario[username]"
              placeholder="ej. sergio.armero"
              required
            />
            <AppShell.field
              :if={@modo == :registro}
              label="Nombre completo"
              name="usuario[nombre_completo]"
              placeholder="Nombre y apellidos"
              required
            />
            <AppShell.select_field
              :if={@modo == :registro}
              label="Zona principal"
              name="usuario[zona_principal]"
              options={@zonas}
              value="Z-01"
              required
            />
            <AppShell.field
              label="Contraseña"
              name="usuario[password]"
              type="password"
              placeholder="Mínimo 8 caracteres"
              required
            />
            <AppShell.field
              :if={@modo == :registro}
              label="Confirmar contraseña"
              name="usuario[password_confirmation]"
              type="password"
              required
            /> <AppShell.notice message={@mensaje} kind={@tipo_mensaje} />
            <button
              type="submit"
              class="w-full rounded-lg bg-orange-600 px-4 py-3 font-semibold text-white transition hover:bg-orange-500"
            >
              {if @modo == :registro, do: "Crear cuenta ciudadana", else: "Ingresar"}
            </button>
          </form>
        </section>
      </div>
    </AppShell.shell>
    """
  end

  defp mensaje(%{"error" => "credenciales_invalidas"}),
    do: "El usuario o la contraseña no son válidos."

  defp mensaje(%{"error" => "contrasenas_distintas"}), do: "Las contraseñas no coinciden."

  defp mensaje(%{"error" => "contrasena_invalida"}),
    do: "Usa una contraseña de al menos ocho caracteres."

  defp mensaje(%{"error" => "usuario_existente"}), do: "Ese nombre de usuario ya está registrado."
  defp mensaje(%{"error" => "zona_requerida"}), do: "Selecciona una zona principal."

  defp mensaje(%{"error" => "codigo_invalido"}),
    do: "El código de zona debe tener el formato Z-01."

  defp mensaje(%{"error" => "zona_no_encontrada"}), do: "Selecciona una zona existente."
  defp mensaje(%{"error" => _}), do: "Completa los campos y revisa los datos ingresados."
  defp mensaje(%{"mensaje" => "sesion_cerrada"}), do: "Sesión cerrada correctamente."
  defp mensaje(_params), do: nil

  defp opciones_zona({:ok, zonas}),
    do: Enum.map(zonas, &{"#{&1.nombre} · #{&1.codigo}", &1.codigo})

  defp opciones_zona(_error), do: []

  defp tab_class(true),
    do: "flex-1 rounded-lg bg-white px-3 py-2.5 text-sm font-semibold text-slate-900 shadow-sm"

  defp tab_class(false),
    do: "flex-1 rounded-lg px-3 py-2.5 text-sm font-medium text-slate-500 hover:text-slate-800"
end
