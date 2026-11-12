defmodule EmergenciasWeb.PanelLive do
  @moduledoc "Panel inicial de la solución y navegación por los módulos de Sergio."
  use EmergenciasWeb, :live_view

  @secciones %{
    inicio: %{
      titulo: "Centro de coordinación",
      descripcion: "Base del sistema de atención y respuesta ante emergencias."
    },
    usuarios: %{
      titulo: "Usuarios y permisos",
      descripcion: "Alta ciudadana, roles y matriz de permisos aprobada."
    },
    zonas: %{
      titulo: "Zonas y atención",
      descripcion: "Zonas de afectación con sectores y puntos de atención."
    },
    albergues: %{
      titulo: "Albergues",
      descripcion: "Capacidad disponible y estancias de personas afectadas."
    }
  }

  @impl true
  def mount(_params, _session, socket), do: cargar(socket, :inicio)

  @impl true
  def handle_params(_params, uri, socket) do
    seccion =
      case URI.parse(uri).path do
        "/usuarios" -> :usuarios
        "/zonas" -> :zonas
        "/albergues" -> :albergues
        _ruta -> :inicio
      end

    datos = Map.fetch!(@secciones, seccion)

    {:noreply,
     assign(socket, seccion: seccion, titulo: datos.titulo, descripcion: datos.descripcion)}
  end

  defp cargar(socket, seccion) do
    datos = Map.get(@secciones, seccion, @secciones.inicio)

    {:ok,
     assign(socket,
       seccion: seccion,
       titulo: datos.titulo,
       descripcion: datos.descripcion,
       estado: Emergencias.API.ping()
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-slate-50 text-slate-900">
      <header class="bg-slate-950 text-white">
        <div class="mx-auto flex max-w-6xl items-center justify-between px-6 py-5">
          <a href="/" class="text-lg font-bold tracking-wide">Emergencias UQ</a>
          <span class="text-sm text-slate-300">Proyecto final · Programación III</span>
        </div>
      </header>
      <div class="mx-auto grid max-w-6xl gap-8 px-6 py-10 md:grid-cols-[230px_1fr]">
        <nav class="space-y-2" aria-label="Módulos">
          <.nav_link href="/" active={@seccion == :inicio}>Resumen</.nav_link>
          <.nav_link href="/usuarios" active={@seccion == :usuarios}>Usuarios y permisos</.nav_link>
          <.nav_link href="/zonas" active={@seccion == :zonas}>Zonas y atención</.nav_link>
          <.nav_link href="/albergues" active={@seccion == :albergues}>Albergues</.nav_link>
          <.nav_link href="/personas" active={false}>Personas afectadas</.nav_link>
          <.nav_link href="/mensajes" active={false}>Mensajes familiares</.nav_link>
        </nav>
        <main>
          <p class="text-sm font-semibold uppercase tracking-widest text-orange-700">
            Módulo de Sergio Armero Salazar
          </p>
          <h1 class="mt-2 text-3xl font-bold">{@titulo}</h1>
          <p class="mt-3 max-w-2xl text-slate-600">{@descripcion}</p>

          <div class="mt-8 rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
            <div class="flex flex-wrap items-center justify-between gap-3">
              <h2 class="text-lg font-semibold">Estado de la aplicación</h2>
              <span class={
                if @estado == {:ok, :pong},
                  do: "rounded-full bg-emerald-100 px-3 py-1 text-sm text-emerald-800",
                  else: "rounded-full bg-amber-100 px-3 py-1 text-sm text-amber-800"
              }>
                {if @estado == {:ok, :pong},
                  do: "Coordinador disponible",
                  else: "Coordinador no disponible"}
              </span>
            </div>
            <p class="mt-2 text-sm text-slate-600">
              La interfaz ya está conectada a la fachada <code>Emergencias.API</code>. El siguiente paso de integración añadirá operaciones y persistencia JSON.
            </p>
          </div>

          <%= if @seccion == :inicio do %>
            <div class="mt-6 grid gap-4 sm:grid-cols-3">
              <.card titulo="Usuarios" detalle="Ciudadanos y roles autorizados" href="/usuarios" />
              <.card titulo="Territorio" detalle="Zonas, sectores y puntos" href="/zonas" />
              <.card titulo="Albergues" detalle="Capacidad y estancias" href="/albergues" />
            </div>
          <% else %>
            <section class="mt-6 rounded-xl border border-dashed border-slate-300 bg-white p-6">
              <h2 class="font-semibold">Base de dominio preparada</h2>
              <p class="mt-2 text-sm leading-6 text-slate-600">
                Esta pantalla identifica el módulo y su responsabilidad. Los formularios de operación quedarán conectados al coordinador cuando se integre el contrato de comandos y el guardado en archivo.
              </p>
            </section>
          <% end %>
        </main>
      </div>
    </div>
    """
  end

  defp nav_link(assigns) do
    ~H"""
    <a
      href={@href}
      class={
        if @active,
          do: "block rounded-lg bg-orange-700 px-4 py-3 text-sm font-semibold text-white",
          else: "block rounded-lg px-4 py-3 text-sm font-medium text-slate-700 hover:bg-white"
      }
    >
      {render_slot(@inner_block)}
    </a>
    """
  end

  defp card(assigns) do
    ~H"""
    <a
      href={@href}
      class="rounded-xl border border-slate-200 bg-white p-5 shadow-sm transition hover:-translate-y-0.5 hover:shadow-md"
    >
      <h2 class="font-semibold">{@titulo}</h2>
      <p class="mt-2 text-sm text-slate-600">{@detalle}</p>
      <span class="mt-4 inline-block text-sm font-semibold text-orange-700">Abrir módulo →</span>
    </a>
    """
  end
end
