defmodule EmergenciasWeb.NecesidadesLive do
  @moduledoc "Pantalla para registrar, filtrar y atender necesidades."
  use EmergenciasWeb, :live_view

  @tipos [
    {"Agua", "agua"},
    {"Alimentos", "alimentos"},
    {"Medicamentos", "medicamentos"},
    {"Primeros auxilios", "primeros_auxilios"},
    {"Refugio", "refugio"},
    {"Transporte", "transporte"},
    {"Rescate", "rescate"},
    {"Otra", "otra"}
  ]

  @prioridades [{"Crítica", "critica"}, {"Alta", "alta"}, {"Media", "media"}, {"Baja", "baja"}]
  @estados [
    {"Pendiente", "pendiente"},
    {"Asignada", "asignada"},
    {"En atención", "en_atencion"},
    {"Atendida", "atendida"},
    {"Cancelada", "cancelada"}
  ]

  @impl true
  def mount(_params, session, socket) do
    socket =
      socket
      |> assign(:session_id, Map.get(session, "session_id"))
      |> assign(:necesidades, [])
      |> assign(:recursos, [])
      |> assign(:mensaje, nil)
      |> assign(:error, nil)
      |> assign(:tipos, @tipos)
      |> assign(:prioridades, @prioridades)
      |> assign(:estados, @estados)
      |> assign(:filtros, %{})
      |> cargar_necesidades()

    {:ok, socket}
  end

  @impl true
  def handle_event("registrar", %{"necesidad" => attrs}, socket) do
    case Emergencias.API.ejecutar(socket.assigns.session_id, {:registrar_necesidad, attrs}) do
      {:ok, _necesidad} ->
        {:noreply,
         socket
         |> assign(:mensaje, "Necesidad registrada.")
         |> assign(:error, nil)
         |> cargar_necesidades()}

      {:error, motivo} ->
        {:noreply, assign(socket, error: error_message(motivo), mensaje: nil)}
    end
  end

  def handle_event("filtrar", %{"filtros" => filtros}, socket) do
    {:noreply,
     socket
     |> assign(:filtros, filtros)
     |> cargar_necesidades()}
  end

  def handle_event("cambiar_estado", %{"id" => id, "estado" => estado}, socket) do
    case Emergencias.API.ejecutar(
           socket.assigns.session_id,
           {:cambiar_estado_necesidad, id, estado}
         ) do
      {:ok, _necesidad} ->
        {:noreply,
         socket
         |> assign(:mensaje, "Estado de la necesidad actualizado.")
         |> assign(:error, nil)
         |> cargar_necesidades()}

      {:error, motivo} ->
        {:noreply, assign(socket, error: error_message(motivo), mensaje: nil)}
    end
  end

  def handle_event("asignar", %{"asignacion" => attrs}, socket) do
    case Emergencias.API.ejecutar(
           socket.assigns.session_id,
           {:asignar_recurso, attrs["necesidad_id"], attrs["recurso_codigo"], attrs["cantidad"]}
         ) do
      {:ok, _asignacion} ->
        {:noreply,
         socket
         |> assign(:mensaje, "Recurso asignado y descontado del inventario.")
         |> assign(:error, nil)
         |> cargar_necesidades()}

      {:error, motivo} ->
        {:noreply, assign(socket, error: error_message(motivo), mensaje: nil)}
    end
  end

  defp cargar_necesidades(%{assigns: %{session_id: nil}} = socket),
    do: assign(socket, error: "Inicia sesión para consultar este módulo.")

  defp cargar_necesidades(socket) do
    case Emergencias.API.consultar(
           socket.assigns.session_id,
           {:necesidades, socket.assigns.filtros}
         ) do
      {:ok, necesidades} ->
        case Emergencias.API.consultar(socket.assigns.session_id, {:recursos, %{}}) do
          {:ok, recursos} ->
            assign(socket, necesidades: necesidades, recursos: recursos, error: nil)

          {:error, motivo} ->
            assign(socket,
              necesidades: necesidades,
              recursos: [],
              error: error_message(motivo)
            )
        end

      {:error, motivo} ->
        assign(socket, necesidades: [], recursos: [], error: error_message(motivo))
    end
  end

  defp recursos_de_zona(recursos, zona_codigo) do
    Enum.filter(recursos, &(&1.zona_codigo == zona_codigo and &1.cantidad_disponible > 0))
  end

  defp acciones_estado(:pendiente), do: [{"Cancelar", "cancelada"}]
  defp acciones_estado(:asignada), do: [{"En atención", "en_atencion"}, {"Cancelar", "cancelada"}]
  defp acciones_estado(:en_atencion), do: [{"Atendida", "atendida"}]
  defp acciones_estado(_estado), do: []

  defp etiqueta_estado(:pendiente), do: "Pendiente"
  defp etiqueta_estado(:asignada), do: "Asignada"
  defp etiqueta_estado(:en_atencion), do: "En atención"
  defp etiqueta_estado(:atendida), do: "Atendida"
  defp etiqueta_estado(:cancelada), do: "Cancelada"
  defp etiqueta_estado(estado), do: to_string(estado)

  defp etiqueta_prioridad(:critica), do: "Crítica"
  defp etiqueta_prioridad(:alta), do: "Alta"
  defp etiqueta_prioridad(:media), do: "Media"
  defp etiqueta_prioridad(:baja), do: "Baja"

  defp error_message(:sesion_invalida), do: "Inicia sesión para usar este módulo."
  defp error_message(:no_autorizado), do: "Tu rol o zona no permite esta acción."
  defp error_message(:datos_incompletos), do: "Completa los campos requeridos."
  defp error_message(:cantidad_invalida), do: "La cantidad debe ser válida y suficiente."
  defp error_message(:stock_insuficiente), do: "No hay inventario suficiente para esa asignación."

  defp error_message(:zona_incompatible),
    do: "El recurso y la necesidad deben pertenecer a la misma zona."

  defp error_message(:prioridad_invalida), do: "Selecciona una prioridad válida."
  defp error_message(:tipo_invalido), do: "Selecciona un tipo de necesidad válido."
  defp error_message(:zona_no_encontrada), do: "La zona indicada no existe."
  defp error_message(:transicion_invalida), do: "Ese cambio de estado no está permitido."
  defp error_message(:error_persistencia), do: "No se pudo guardar el cambio."
  defp error_message(_motivo), do: "No se pudo completar la operación."

  @impl true
  def render(assigns) do
    ~H"""
    <main class="min-h-screen bg-slate-50 text-slate-900">
      <header class="bg-slate-950 px-6 py-5 text-white">
        <div class="mx-auto flex max-w-6xl items-center justify-between">
          <a href="/" class="font-bold">Emergencias UQ</a>
          <a href="/recursos" class="text-sm text-orange-200 hover:text-white">Ir a recursos</a>
        </div>
      </header>

      <div class="mx-auto max-w-6xl space-y-8 px-6 py-10">
        <div>
          <p class="text-sm font-semibold uppercase tracking-widest text-orange-700">
            Módulo de necesidades
          </p>

          <h1 class="mt-2 text-3xl font-bold">Necesidades y prioridades</h1>

          <p class="mt-2 max-w-3xl text-slate-600">
            Registra solicitudes de ayuda y consulta su estado. Las necesidades se ordenan por prioridad y fecha de registro.
          </p>
        </div>

        <p :if={@mensaje} role="status" class="rounded-lg bg-emerald-100 p-3 text-emerald-900">
          {@mensaje}
        </p>

        <p :if={@error} role="alert" class="rounded-lg bg-rose-100 p-3 text-rose-900">
          {@error}
          <a :if={is_nil(@session_id)} href="/usuarios" class="ml-2 font-semibold underline">Iniciar sesión</a>
        </p>

        <section class="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
          <h2 class="text-xl font-semibold">Registrar necesidad</h2>

          <form :if={@session_id} phx-submit="registrar" class="mt-5 grid gap-4 md:grid-cols-2">
            <label class="grid gap-1 text-sm font-medium">
              Tipo
              <select name="necesidad[tipo]" required class="rounded-lg border border-slate-300 p-2">
                <option value="">Selecciona</option>

                <option :for={{label, value} <- @tipos} value={value}>{label}</option>
              </select>
            </label>

            <label class="grid gap-1 text-sm font-medium">
              Zona
              <input
                name="necesidad[zona_codigo]"
                required
                class="rounded-lg border border-slate-300 p-2"
              />
            </label>

            <label class="grid gap-1 text-sm font-medium">
              Cantidad requerida
              <input
                name="necesidad[cantidad]"
                type="number"
                min="0"
                required
                class="rounded-lg border border-slate-300 p-2"
              />
            </label>

            <label class="grid gap-1 text-sm font-medium">
              Prioridad
              <select
                name="necesidad[prioridad]"
                required
                class="rounded-lg border border-slate-300 p-2"
              >
                <option :for={{label, value} <- @prioridades} value={value}>{label}</option>
              </select>
            </label>

            <label class="grid gap-1 text-sm font-medium md:col-span-2">
              Descripción <textarea
                name="necesidad[descripcion]"
                required
                rows="3"
                class="rounded-lg border border-slate-300 p-2"
              ></textarea>
            </label>

            <div class="md:col-span-2">
              <button
                type="submit"
                class="rounded-lg bg-orange-700 px-4 py-2 font-semibold text-white hover:bg-orange-800"
                phx-disable-with="Guardando..."
              >
                Registrar
              </button>
            </div>
          </form>
        </section>

        <section class="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
          <div class="flex flex-wrap items-end justify-between gap-4">
            <div>
              <h2 class="text-xl font-semibold">Solicitudes</h2>

              <p class="mt-1 text-sm text-slate-600">
                Las consultas quedan limitadas a tu zona según tu sesión.
              </p>
            </div>

            <form :if={@session_id} phx-change="filtrar" class="grid gap-3 sm:grid-cols-4">
              <input
                name="filtros[zona_codigo]"
                placeholder="Zona"
                class="rounded-lg border border-slate-300 p-2 text-sm"
              />
              <select name="filtros[tipo]" class="rounded-lg border border-slate-300 p-2 text-sm">
                <option value="">Todos los tipos</option>

                <option :for={{label, value} <- @tipos} value={value}>{label}</option>
              </select>

              <select name="filtros[prioridad]" class="rounded-lg border border-slate-300 p-2 text-sm">
                <option value="">Todas las prioridades</option>

                <option :for={{label, value} <- @prioridades} value={value}>{label}</option>
              </select>

              <select name="filtros[estado]" class="rounded-lg border border-slate-300 p-2 text-sm">
                <option value="">Todos los estados</option>

                <option :for={{label, value} <- @estados} value={value}>{label}</option>
              </select>
            </form>
          </div>

          <div :if={@necesidades == []} class="mt-6 rounded-lg bg-slate-50 p-5 text-slate-600">
            No hay necesidades para mostrar con estos filtros.
          </div>

          <div :if={@necesidades != []} class="mt-6 overflow-x-auto">
            <table class="w-full min-w-[700px] text-left text-sm">
              <thead class="border-b border-slate-200 text-slate-500">
                <tr>
                  <th class="py-3 pr-3">Solicitud</th>

                  <th class="py-3 pr-3">Zona</th>

                  <th class="py-3 pr-3">Cantidad</th>

                  <th class="py-3 pr-3">Prioridad</th>

                  <th class="py-3 pr-3">Estado</th>

                  <th class="py-3">Acción</th>
                </tr>
              </thead>

              <tbody>
                <tr :for={necesidad <- @necesidades} class="border-b border-slate-100 align-top">
                  <td class="py-4 pr-3">
                    <div class="font-semibold">{necesidad.tipo}</div>

                    <div class="mt-1 max-w-sm text-slate-600">{necesidad.descripcion}</div>

                    <div class="mt-1 text-xs text-slate-400">{necesidad.id}</div>
                  </td>

                  <td class="py-4 pr-3">{necesidad.zona_codigo}</td>

                  <td class="py-4 pr-3">{necesidad.cantidad}</td>

                  <td class="py-4 pr-3">{etiqueta_prioridad(necesidad.prioridad)}</td>

                  <td class="py-4 pr-3">{etiqueta_estado(necesidad.estado)}</td>

                  <td class="py-4">
                    <form
                      :if={
                        necesidad.estado in [:pendiente, :asignada] and
                          recursos_de_zona(@recursos, necesidad.zona_codigo) != []
                      }
                      phx-submit="asignar"
                      class="mb-2 flex flex-wrap gap-2"
                    >
                      <input type="hidden" name="asignacion[necesidad_id]" value={necesidad.id} />
                      <select
                        name="asignacion[recurso_codigo]"
                        required
                        class="max-w-44 rounded-md border border-slate-300 p-1 text-xs"
                      >
                        <option value="">Recurso</option>

                        <option
                          :for={recurso <- recursos_de_zona(@recursos, necesidad.zona_codigo)}
                          value={recurso.codigo}
                        >
                          {recurso.nombre} ({recurso.cantidad_disponible} {recurso.unidad})
                        </option>
                      </select>

                      <input
                        name="asignacion[cantidad]"
                        type="number"
                        min="1"
                        required
                        placeholder="Cantidad"
                        class="w-24 rounded-md border border-slate-300 p-1 text-xs"
                      />
                      <button
                        type="submit"
                        class="rounded-md bg-orange-700 px-2 py-1 text-xs font-semibold text-white"
                        phx-disable-with="Asignando..."
                      >
                        Asignar
                      </button>
                    </form>

                    <div :if={acciones_estado(necesidad.estado) != []} class="flex flex-wrap gap-2">
                      <button
                        :for={{label, estado} <- acciones_estado(necesidad.estado)}
                        type="button"
                        phx-click="cambiar_estado"
                        phx-value-id={necesidad.id}
                        phx-value-estado={estado}
                        class="rounded-md border border-slate-300 px-2 py-1 text-xs font-semibold hover:bg-slate-100"
                      >
                        {label}
                      </button>
                    </div>

                    <span :if={acciones_estado(necesidad.estado) == []} class="text-slate-400">—</span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
      </div>
    </main>
    """
  end
end
