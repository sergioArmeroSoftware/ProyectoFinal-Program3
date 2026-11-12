defmodule EmergenciasWeb.PanelLive do
  @moduledoc "Panel de inicio del sistema de coordinación de emergencias."
  use EmergenciasWeb, :live_view

  alias EmergenciasWeb.AppShell

  @modulos [
    {"Usuarios", "/usuarios", "Registro, roles y permisos.", "♙"},
    {"Zonas y atención", "/zonas", "Sectores y puntos de atención.", "⌖"},
    {"Albergues", "/albergues", "Capacidad, ocupación y estancias.", "⌂"},
    {"Personas", "/personas", "Registro y seguimiento de personas afectadas.", "♧"},
    {"Mensajes", "/mensajes", "Comunicación con familiares.", "✉"},
    {"Mascotas", "/mascotas", "Reportes y búsqueda de coincidencias.", "♡"},
    {"Necesidades", "/necesidades", "Solicitudes y prioridades de atención.", "!"},
    {"Recursos", "/recursos", "Inventario, asignaciones y transferencias.", "▦"}
  ]

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, estado: Emergencias.API.ping())}

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :modulos, @modulos)

    ~H"""
    <AppShell.shell
      title="Resumen"
      current_path="/"
      current_user={@current_user}
      csrf_token={@csrf_token}
      flash={@flash}
    >
      <section class="overflow-hidden rounded-3xl bg-gradient-to-br from-slate-950 via-slate-900 to-slate-800 text-white shadow-xl">
        <div class="grid gap-8 px-7 py-10 sm:px-10 sm:py-14 lg:grid-cols-[1.2fr_0.8fr] lg:items-center">
          <div>
            <p class="text-sm font-bold uppercase tracking-[0.2em] text-orange-400">
              Panel de coordinación
            </p>
            <h1 class="mt-4 max-w-2xl text-4xl font-black leading-tight sm:text-5xl">
              Atención organizada para responder mejor.
            </h1>
            <p class="mt-5 max-w-xl leading-7 text-slate-300">
              Hola, {@current_user.nombre_completo}. Consulta los módulos disponibles para tu rol.
            </p>
          </div>
          <div class="rounded-2xl border border-white/10 bg-white/5 p-6 backdrop-blur">
            <div class="flex items-center justify-between gap-4">
              <div>
                <p class="text-sm text-slate-300">Conexión con coordinador</p>
                <p class="mt-1 text-xl font-bold">{estado_texto(@estado)}</p>
              </div>
              <span class={
                if @estado == {:ok, :pong},
                  do: "size-3 rounded-full bg-emerald-400",
                  else: "size-3 rounded-full bg-amber-400"
              } />
            </div>
            <p class="mt-4 text-sm leading-6 text-slate-400">
              Los cambios se procesan mediante el coordinador y se guardan en el snapshot JSON.
            </p>
          </div>
        </div>
      </section>

      <div class="mt-8">
        <p class="text-sm font-semibold uppercase tracking-widest text-orange-700">
          Módulos del proyecto
        </p>
        <h2 class="mt-1 text-2xl font-bold">Acceso rápido</h2>
      </div>

      <div class="mt-5 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <.module_card
          :for={{title, href, detail, icon} <- @modulos}
          title={title}
          href={href}
          detail={detail}
          icon={icon}
        />
      </div>
    </AppShell.shell>
    """
  end

  defp estado_texto({:ok, :pong}), do: "Disponible"
  defp estado_texto(_estado), do: "En integración"

  defp module_card(assigns) do
    ~H"""
    <a
      href={@href}
      class="group rounded-2xl border border-slate-200 bg-white p-5 shadow-sm transition hover:-translate-y-1 hover:border-orange-300 hover:shadow-md"
    >
      <span class="grid size-11 place-items-center rounded-xl bg-orange-50 text-2xl text-orange-700">{@icon}</span>
      <h3 class="mt-5 text-lg font-bold group-hover:text-orange-700">{@title}</h3>
      <p class="mt-1 text-sm text-slate-600">{@detail}</p>
      <span class="mt-5 inline-flex text-sm font-semibold text-orange-700">Abrir módulo →</span>
    </a>
    """
  end
end
