defmodule EmergenciasWeb.PanelLive do
  @moduledoc "Inicio de la interfaz de coordinación de emergencias."
  use EmergenciasWeb, :live_view

  alias EmergenciasWeb.AppShell

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, estado: Emergencias.API.ping())}

  @impl true
  def render(assigns) do
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
              Hola, {@current_user.nombre_completo}. Consulta las funciones disponibles para tu rol.
            </p>
            <a
              href="/zonas"
              class="mt-7 inline-flex items-center rounded-lg bg-orange-600 px-5 py-3 font-semibold text-white transition hover:bg-orange-500"
            >
              Explorar el sistema <span class="ml-2" aria-hidden="true">→</span>
            </a>
          </div>
          <div class="rounded-2xl border border-white/10 bg-white/5 p-6 backdrop-blur">
            <div class="flex items-center justify-between gap-4">
              <div>
                <p class="text-sm text-slate-300">Conexión con coordinador</p>
                <p class="mt-1 text-xl font-bold">{@estado |> estado_texto()}</p>
              </div>
              <span class={
                if @estado == {:ok, :pong},
                  do: "size-3 rounded-full bg-emerald-400",
                  else: "size-3 rounded-full bg-amber-400"
              } />
            </div>
            <p class="mt-4 text-sm leading-6 text-slate-400">
              Las pantallas de trabajo usan datos temporales de demostración hasta conectar las operaciones con el nodo coordinador.
            </p>
          </div>
        </div>
      </section>

      <div class="mt-8 flex flex-wrap items-end justify-between gap-3">
        <div>
          <p class="text-sm font-semibold uppercase tracking-widest text-orange-700">
            Módulos del proyecto
          </p>
          <h2 class="mt-1 text-2xl font-bold">Acceso rápido</h2>
        </div>
        <span class="rounded-full bg-amber-100 px-3 py-1.5 text-xs font-semibold text-amber-900">Prototipo de interfaz</span>
      </div>

      <div class="mt-5 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <.module_card
          href="/usuarios"
          number="01"
          title="Usuarios"
          detail="Registro, roles y permisos."
          icon="♙"
        />
        <.module_card
          href="/zonas"
          number="02"
          title="Zonas y atención"
          detail="Sectores y puntos de atención."
          icon="⌖"
        />
        <.module_card
          href="/albergues"
          number="03"
          title="Albergues"
          detail="Capacidad, ocupación y estancias."
          icon="⌂"
        />
        <.module_card
          href="/acceso"
          number="04"
          title="Acceso"
          detail="Ingreso y registro de cuenta."
          icon="↗"
        />
      </div>

      <section class="mt-8 rounded-2xl border border-slate-200 bg-white p-5 sm:p-6">
        <h2 class="font-bold">Estado de desarrollo</h2>
        <div class="mt-4 grid gap-3 text-sm sm:grid-cols-3">
          <.status_item title="Usuarios y territorio" text="Reglas de dominio preparadas por Sergio" />
          <.status_item title="Coordinador" text="Pendiente de integrar comandos y persistencia" />
          <.status_item
            title="Personas y estancias"
            text="Pendiente de integrar historial de personas"
          />
        </div>
      </section>
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
      <div class="flex items-start justify-between">
        <span class="grid size-11 place-items-center rounded-xl bg-orange-50 text-2xl text-orange-700">{@icon}</span>
        <span class="text-xs font-bold tracking-widest text-slate-400">{@number}</span>
      </div>
      <h3 class="mt-5 text-lg font-bold group-hover:text-orange-700">{@title}</h3>
      <p class="mt-1 text-sm text-slate-600">{@detail}</p>
      <span class="mt-5 inline-flex text-sm font-semibold text-orange-700">Abrir módulo
      <span class="ml-1">→</span></span>
    </a>
    """
  end

  defp status_item(assigns) do
    ~H"""
    <div class="rounded-xl bg-slate-50 p-4">
      <p class="font-semibold text-slate-800">{@title}</p>
      <p class="mt-1 leading-5 text-slate-600">{@text}</p>
    </div>
    """
  end
end
