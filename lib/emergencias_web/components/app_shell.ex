defmodule EmergenciasWeb.AppShell do
  @moduledoc "Componentes compartidos de navegación y presentación."
  use Phoenix.Component

  attr :title, :string, required: true
  attr :current_path, :string, default: "/"
  attr :current_user, :map, default: nil
  attr :csrf_token, :string, default: nil
  attr :flash, :map, default: %{}
  slot :inner_block, required: true

  def shell(assigns) do
    ~H"""
    <div class="min-h-screen bg-slate-50 text-slate-900">
      <header class="bg-slate-950 text-white shadow">
        <div class="mx-auto flex max-w-7xl flex-wrap items-center justify-between gap-4 px-5 py-4 sm:px-8">
          <a href="/" class="flex items-center gap-3">
            <span class="grid size-10 place-items-center rounded-xl bg-orange-600 text-xl font-black">E</span>
            <span>
              <span class="block text-lg font-bold leading-tight">Emergencias UQ</span>
              <span class="text-xs text-slate-300">Coordinación y atención</span>
            </span>
          </a>
          <nav class="flex flex-wrap items-center gap-1 text-sm" aria-label="Navegación principal">
            <.nav_link href="/" current={@current_path}>Inicio</.nav_link>
            <.nav_link :if={is_nil(@current_user)} href="/acceso" current={@current_path}>Acceso</.nav_link>
            <.nav_link :if={@current_user} href="/usuarios" current={@current_path}>Usuarios</.nav_link>
            <.nav_link :if={@current_user} href="/zonas" current={@current_path}>Zonas</.nav_link>
            <.nav_link :if={@current_user} href="/albergues" current={@current_path}>Albergues</.nav_link>
            <div
              :if={@current_user}
              class="ml-2 flex items-center gap-3 border-l border-white/15 pl-3"
            >
              <span class="text-right text-xs">
                <span class="block font-semibold">{@current_user.nombre_completo}</span>
                <span class="text-slate-300">{humanizar(@current_user.rol)}</span>
              </span>
              <form action="/sesion" method="post">
                <input type="hidden" name="_method" value="delete" />
                <input type="hidden" name="_csrf_token" value={@csrf_token} />
                <button class="rounded-lg border border-white/20 px-3 py-2 text-xs font-semibold hover:bg-white/10">Cerrar sesión</button>
              </form>
            </div>
          </nav>
        </div>
      </header>

      <main class="mx-auto max-w-7xl px-5 py-8 sm:px-8 sm:py-10">
        <.notice
          :if={Phoenix.Flash.get(@flash, :error)}
          message={Phoenix.Flash.get(@flash, :error)}
          kind="error"
        />
        {render_slot(@inner_block)}
      </main>

      <footer class="border-t border-slate-200 bg-white">
        <div class="mx-auto flex max-w-7xl flex-wrap items-center justify-between gap-2 px-5 py-4 text-xs text-slate-500 sm:px-8">
          <span>Proyecto final · Programación III · Universidad del Quindío</span>
          <span>Interfaz de trabajo en desarrollo</span>
        </div>
      </footer>
    </div>
    """
  end

  attr :href, :string, required: true
  attr :current, :string, required: true
  slot :inner_block, required: true

  def nav_link(assigns) do
    ~H"""
    <a
      href={@href}
      class={
        if @current == @href,
          do: "rounded-lg bg-white/15 px-3 py-2 font-semibold text-white",
          else: "rounded-lg px-3 py-2 text-slate-300 transition hover:bg-white/10 hover:text-white"
      }
    >
      {render_slot(@inner_block)}
    </a>
    """
  end

  defp humanizar(value) when is_atom(value),
    do: value |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()

  defp humanizar(value), do: to_string(value)

  attr :title, :string, required: true
  attr :description, :string, default: nil
  slot :inner_block, required: true

  def panel(assigns) do
    ~H"""
    <section class="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm sm:p-6">
      <div class="mb-5">
        <h2 class="text-lg font-bold">{@title}</h2>
        <%= if @description do %>
          <p class="mt-1 text-sm text-slate-600">{@description}</p>
        <% end %>
      </div>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :label, :string, required: true
  attr :name, :string, required: true
  attr :type, :string, default: "text"
  attr :value, :string, default: ""
  attr :placeholder, :string, default: ""
  attr :required, :boolean, default: false
  attr :min, :string, default: nil
  attr :step, :string, default: nil
  attr :pattern, :string, default: nil
  attr :title, :string, default: nil
  attr :error, :string, default: nil
  attr :hint, :string, default: nil

  def field(assigns) do
    ~H"""
    <label class="block space-y-1.5 text-sm font-medium text-slate-700">
      <span>{@label}</span>
      <input
        type={@type}
        name={@name}
        value={@value}
        placeholder={@placeholder}
        required={@required}
        min={@min}
        step={@step}
        pattern={@pattern}
        title={@title}
        aria-invalid={if @error, do: "true", else: "false"}
        class="w-full rounded-lg border border-slate-300 bg-white px-3 py-2.5 text-slate-900 outline-none transition placeholder:text-slate-400 focus:border-orange-500 focus:ring-2 focus:ring-orange-100"
      />
      <span :if={@error} class="block text-xs font-normal text-rose-700">{@error}</span>
      <span :if={is_nil(@error) and @hint} class="block text-xs font-normal text-slate-500">{@hint}</span>
    </label>
    """
  end

  attr :label, :string, required: true
  attr :name, :string, required: true
  attr :options, :list, required: true
  attr :value, :string, default: ""
  attr :required, :boolean, default: false
  attr :error, :string, default: nil

  def select_field(assigns) do
    ~H"""
    <label class="block space-y-1.5 text-sm font-medium text-slate-700">
      <span>{@label}</span>
      <select
        name={@name}
        required={@required}
        aria-invalid={if @error, do: "true", else: "false"}
        class="w-full rounded-lg border border-slate-300 bg-white px-3 py-2.5 text-slate-900 outline-none focus:border-orange-500 focus:ring-2 focus:ring-orange-100"
      >
        <option :for={{label, value} <- @options} value={value} selected={@value == value}>
          {label}
        </option>
      </select>
      <span :if={@error} class="block text-xs font-normal text-rose-700">{@error}</span>
    </label>
    """
  end

  attr :message, :string, default: nil
  attr :kind, :string, default: "info"

  def notice(assigns) do
    ~H"""
    <div :if={@message} role="status" class={notice_class(@kind)}>{@message}</div>
    """
  end

  defp notice_class("error"),
    do: "rounded-lg border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-800"

  defp notice_class("success"),
    do: "rounded-lg border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-800"

  defp notice_class(_kind),
    do: "rounded-lg border border-blue-200 bg-blue-50 px-4 py-3 text-sm text-blue-800"
end
