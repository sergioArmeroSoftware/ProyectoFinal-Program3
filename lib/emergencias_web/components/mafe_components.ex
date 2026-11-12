defmodule EmergenciasWeb.MafeComponents do
  @moduledoc "Componentes visuales de los módulos de Maria Fernanda, con el estilo del panel."
  use EmergenciasWeb, :html

  attr :titulo, :string, required: true
  attr :descripcion, :string, required: true
  attr :seccion, :atom, default: :personas
  slot :inner_block, required: true

  @doc "Conserva el encabezado, navegación lateral y distribución del panel existente."
  def modulo(assigns) do
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
          <.enlace href="/">Resumen</.enlace>
          <.enlace href="/usuarios">Usuarios y permisos</.enlace>
          <.enlace href="/zonas">Zonas y atención</.enlace>
          <.enlace href="/albergues">Albergues</.enlace>
          <.enlace href="/personas" activo={@seccion == :personas}>Personas afectadas</.enlace>
          <.enlace href="/mensajes" activo={@seccion == :mensajes}>Mensajes familiares</.enlace>
        </nav>
        <main class="min-w-0">
          <p class="text-sm font-semibold uppercase tracking-widest text-orange-700">
            MÓDULO DE MARIA FERNANDA MEJÍA OCAMPO
          </p>
          <h1 class="mt-2 text-3xl font-bold">{@titulo}</h1>
          <p class="mt-3 max-w-2xl text-slate-600">{@descripcion}</p>
          <div class="mt-8 space-y-6">{render_slot(@inner_block)}</div>
        </main>
      </div>
    </div>
    """
  end

  attr :href, :string, required: true
  attr :activo, :boolean, default: false
  slot :inner_block, required: true

  defp enlace(assigns) do
    ~H"""
    <a
      href={@href}
      aria-current={@activo && "page"}
      class={
        if @activo,
          do: "block rounded-lg bg-orange-700 px-4 py-3 text-sm font-semibold text-white",
          else: "block rounded-lg px-4 py-3 text-sm font-medium text-slate-700 hover:bg-white"
      }
    >
      {render_slot(@inner_block)}
    </a>
    """
  end

  attr :id, :string, required: true
  attr :titulo, :string, required: true
  slot :inner_block, required: true
  @doc "Tarjeta blanca con los bordes, sombra y espaciados del panel."
  def tarjeta(assigns) do
    ~H"""
    <section id={@id} class="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
      <h2 class="text-lg font-semibold">{@titulo}</h2>
      <div class="mt-4">{render_slot(@inner_block)}</div>
    </section>
    """
  end

  attr :estado, :atom, required: true
  @doc "Indicador discreto del estado de una persona."
  def estado_persona(assigns) do
    ~H"""
    <span class={
      if @estado == :reunificada,
        do: "rounded-full bg-emerald-100 px-3 py-1 text-sm text-emerald-800",
        else: "rounded-full bg-slate-100 px-3 py-1 text-sm text-slate-700"
    }>
      {etiqueta_estado(@estado)}
    </span>
    """
  end

  @doc "Etiqueta legible de los estados acordados de personas."
  def etiqueta_estado(:sin_informacion), do: "Sin información"
  def etiqueta_estado(:reportada), do: "Reportada"
  def etiqueta_estado(:localizada), do: "Localizada"
  def etiqueta_estado(:trasladada), do: "Trasladada"
  def etiqueta_estado(:en_albergue), do: "En albergue"
  def etiqueta_estado(:reunificada), do: "Reunificada"

  @doc "Traduce errores funcionales sin exponer detalles internos."
  def mensaje_error(:sesion_invalida),
    do: "La sesión no es válida. Necesitas una sesión activa para continuar."

  def mensaje_error(:no_autorizado),
    do: "Tu rol, zona o relación con este reporte no permite la operación."

  def mensaje_error(:no_encontrado), do: "El registro no está disponible para esta sesión."
  def mensaje_error(:datos_incompletos), do: "Completa los campos obligatorios con datos válidos."

  def mensaje_error(:cantidad_invalida),
    do: "La edad debe ser un número entero mayor o igual a cero."

  def mensaje_error(:zona_no_encontrada), do: "Selecciona una zona disponible."
  def mensaje_error(:estado_invalido), do: "Selecciona un estado válido."
  def mensaje_error(:transicion_invalida), do: "Ese cambio de estado no está permitido."
  def mensaje_error(:ya_resuelto), do: "La persona está reunificada y su estado es final."

  def mensaje_error(:error_persistencia),
    do: "No se pudo guardar el cambio. Los datos anteriores se conservaron."

  def mensaje_error(:coordinador_no_disponible),
    do: "El coordinador no está disponible. Intenta nuevamente."

  def mensaje_error(_motivo), do: "No se pudo completar la operación. Intenta nuevamente."
end
