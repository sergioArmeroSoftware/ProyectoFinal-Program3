defmodule EmergenciasWeb.RecursosLive do
  @moduledoc "Pantalla para registrar, consultar y transferir inventario."
  use EmergenciasWeb, :live_view

  @impl true
  def mount(_params, session, socket) do
    socket =
      socket
      |> assign(:session_id, Map.get(session, "session_id"))
      |> assign(:recursos, [])
      |> assign(:movimientos, [])
      |> assign(:mensaje, nil)
      |> assign(:error, nil)
      |> assign(:filtros, %{})
      |> assign(:ver_criticos, false)
      |> cargar_datos()

    {:ok, socket}
  end

  @impl true
  def handle_event("registrar", %{"recurso" => attrs}, socket) do
    case Emergencias.API.ejecutar(socket.assigns.session_id, {:registrar_recurso, attrs}) do
      {:ok, _recurso} ->
        {:noreply,
         socket
         |> assign(:mensaje, "Recurso registrado y movimiento de entrada guardado.")
         |> assign(:error, nil)
         |> cargar_datos()}

      {:error, motivo} ->
        {:noreply, assign(socket, error: error_message(motivo), mensaje: nil)}
    end
  end

  def handle_event("ingresar", %{"ingreso" => attrs}, socket) do
    case Emergencias.API.ejecutar(
           socket.assigns.session_id,
           {:ingresar_recurso, attrs["recurso_codigo"], attrs["cantidad"]}
         ) do
      {:ok, _resultado} ->
        {:noreply,
         socket
         |> assign(:mensaje, "Entrada de inventario registrada.")
         |> assign(:error, nil)
         |> cargar_datos()}

      {:error, motivo} ->
        {:noreply, assign(socket, error: error_message(motivo), mensaje: nil)}
    end
  end

  def handle_event("filtrar", %{"filtros" => filtros}, socket) do
    {:noreply,
     socket
     |> assign(:filtros, filtros)
     |> assign(:ver_criticos, false)
     |> cargar_datos()}
  end

  def handle_event("ver_criticos", _params, socket) do
    {:noreply,
     socket
     |> assign(:ver_criticos, true)
     |> cargar_datos()}
  end

  def handle_event("ver_todos", _params, socket) do
    {:noreply,
     socket
     |> assign(:ver_criticos, false)
     |> cargar_datos()}
  end

  def handle_event("transferir", %{"transferencia" => attrs}, socket) do
    recurso_codigo = Map.get(attrs, "recurso_codigo")
    origen = Map.get(attrs, "origen")
    destino = Map.get(attrs, "destino")
    cantidad = Map.get(attrs, "cantidad")

    case Emergencias.API.ejecutar(
           socket.assigns.session_id,
           {:transferir_recurso, recurso_codigo, origen, destino, cantidad}
         ) do
      {:ok, _resultado} ->
        {:noreply,
         socket
         |> assign(:mensaje, "Transferencia registrada en el historial.")
         |> assign(:error, nil)
         |> cargar_datos()}

      {:error, motivo} ->
        {:noreply, assign(socket, error: error_message(motivo), mensaje: nil)}
    end
  end

  defp cargar_datos(%{assigns: %{session_id: nil}} = socket),
    do: assign(socket, error: "Inicia sesión para consultar este módulo.")

  defp cargar_datos(socket) do
    consulta =
      if socket.assigns.ver_criticos,
        do: {:recursos_criticos, socket.assigns.filtros},
        else: {:recursos, socket.assigns.filtros}

    case Emergencias.API.consultar(socket.assigns.session_id, consulta) do
      {:ok, recursos} ->
        case Emergencias.API.consultar(socket.assigns.session_id, {:movimientos, %{}}) do
          {:ok, movimientos} ->
            assign(socket, recursos: recursos, movimientos: movimientos, error: nil)

          {:error, motivo} ->
            assign(socket, recursos: recursos, movimientos: [], error: error_message(motivo))
        end

      {:error, motivo} ->
        assign(socket, recursos: [], movimientos: [], error: error_message(motivo))
    end
  end

  defp error_message(:sesion_invalida), do: "Inicia sesión para usar este módulo."
  defp error_message(:no_autorizado), do: "Tu rol o zona no permite esta acción."
  defp error_message(:datos_incompletos), do: "Completa los campos requeridos."
  defp error_message(:cantidad_invalida), do: "La cantidad debe ser un entero positivo."
  defp error_message(:stock_insuficiente), do: "No hay inventario suficiente."
  defp error_message(:id_duplicado), do: "Ese código ya está registrado."
  defp error_message(:no_encontrado), do: "No se encontró el recurso indicado."
  defp error_message(:zona_no_encontrada), do: "La zona indicada no existe."
  defp error_message(:origen_invalido), do: "El origen no coincide con la ubicación actual."
  defp error_message(:destino_invalido), do: "Selecciona una ubicación distinta al origen."
  defp error_message(:error_persistencia), do: "No se pudo guardar el cambio."
  defp error_message(_motivo), do: "No se pudo completar la operación."

  defp fecha(%DateTime{} = value), do: Calendar.strftime(value, "%Y-%m-%d %H:%M")
  defp fecha(_value), do: "Sin fecha"

  @impl true
  def render(assigns) do
    ~H"""
    <main class="min-h-screen bg-slate-50 text-slate-900">
      <header class="bg-slate-950 px-6 py-5 text-white">
        <div class="mx-auto flex max-w-6xl items-center justify-between">
          <a href="/" class="font-bold">Emergencias UQ</a>
          <a href="/necesidades" class="text-sm text-orange-200 hover:text-white">Ir a necesidades</a>
        </div>
      </header>
      <div class="mx-auto max-w-6xl space-y-8 px-6 py-10">
        <div>
          <p class="text-sm font-semibold uppercase tracking-widest text-orange-700">Módulo de recursos</p>
          <h1 class="mt-2 text-3xl font-bold">Inventario y transferencias</h1>
          <p class="mt-2 max-w-3xl text-slate-600">
            Registra existencias, consulta inventario por categoría o ubicación y conserva el historial de movimientos.
          </p>
        </div>

        <p :if={@mensaje} role="status" class="rounded-lg bg-emerald-100 p-3 text-emerald-900">{@mensaje}</p>
        <p :if={@error} role="alert" class="rounded-lg bg-rose-100 p-3 text-rose-900">
          {@error}
          <a :if={is_nil(@session_id)} href="/usuarios" class="ml-2 font-semibold underline">Iniciar sesión</a>
        </p>

        <section class="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
          <h2 class="text-xl font-semibold">Registrar recurso</h2>
          <form :if={@session_id} phx-submit="registrar" class="mt-5 grid gap-4 md:grid-cols-3">
            <label class="grid gap-1 text-sm font-medium">Código
              <input name="recurso[codigo]" required class="rounded-lg border border-slate-300 p-2" />
            </label>
            <label class="grid gap-1 text-sm font-medium">Nombre
              <input name="recurso[nombre]" required class="rounded-lg border border-slate-300 p-2" />
            </label>
            <label class="grid gap-1 text-sm font-medium">Categoría
              <input name="recurso[categoria]" required class="rounded-lg border border-slate-300 p-2" />
            </label>
            <label class="grid gap-1 text-sm font-medium">Cantidad disponible
              <input name="recurso[cantidad_disponible]" type="number" min="0" required class="rounded-lg border border-slate-300 p-2" />
            </label>
            <label class="grid gap-1 text-sm font-medium">Unidad
              <input name="recurso[unidad]" required class="rounded-lg border border-slate-300 p-2" />
            </label>
            <label class="grid gap-1 text-sm font-medium">Zona
              <input name="recurso[zona_codigo]" required class="rounded-lg border border-slate-300 p-2" />
            </label>
            <label class="grid gap-1 text-sm font-medium md:col-span-2">Ubicación
              <input name="recurso[ubicacion]" required class="rounded-lg border border-slate-300 p-2" />
            </label>
            <div class="flex items-end">
              <button type="submit" class="rounded-lg bg-orange-700 px-4 py-2 font-semibold text-white hover:bg-orange-800" phx-disable-with="Guardando...">
                Registrar
              </button>
            </div>
          </form>
        </section>

        <section class="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
          <div class="flex flex-wrap items-end justify-between gap-4">
            <div>
              <h2 class="text-xl font-semibold">Inventario</h2>
              <p class="mt-1 text-sm text-slate-600">Las consultas quedan limitadas a tu zona según tu sesión.</p>
            </div>
            <div :if={@session_id} class="flex flex-wrap items-end gap-3">
              <form phx-change="filtrar" class="grid gap-3 sm:grid-cols-4">
                <input name="filtros[zona_codigo]" placeholder="Zona" class="rounded-lg border border-slate-300 p-2 text-sm" />
                <input name="filtros[categoria]" placeholder="Categoría" class="rounded-lg border border-slate-300 p-2 text-sm" />
                <input name="filtros[ubicacion]" placeholder="Ubicación" class="rounded-lg border border-slate-300 p-2 text-sm" />
                <input name="filtros[codigo]" placeholder="Código" class="rounded-lg border border-slate-300 p-2 text-sm" />
              </form>
              <button
                :if={!@ver_criticos}
                type="button"
                phx-click="ver_criticos"
                class="rounded-lg border border-orange-700 px-3 py-2 text-sm font-semibold text-orange-800"
              >
                Ver sin stock
              </button>
              <button
                :if={@ver_criticos}
                type="button"
                phx-click="ver_todos"
                class="rounded-lg border border-slate-300 px-3 py-2 text-sm font-semibold"
              >
                Ver todos
              </button>
            </div>
          </div>

          <div :if={@recursos == []} class="mt-6 rounded-lg bg-slate-50 p-5 text-slate-600">
            No hay recursos para mostrar con estos filtros.
          </div>
          <div :if={@recursos != []} class="mt-6 overflow-x-auto">
            <table class="w-full min-w-[700px] text-left text-sm">
              <thead class="border-b border-slate-200 text-slate-500">
                <tr>
                  <th class="py-3 pr-3">Recurso</th>
                  <th class="py-3 pr-3">Categoría</th>
                  <th class="py-3 pr-3">Disponible</th>
                  <th class="py-3 pr-3">Ubicación</th>
                  <th class="py-3">Zona</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={recurso <- @recursos} class="border-b border-slate-100">
                  <td class="py-3 pr-3"><span class="font-semibold">{recurso.nombre}</span><span class="ml-2 text-xs text-slate-400">{recurso.codigo}</span></td>
                  <td class="py-3 pr-3">{recurso.categoria}</td>
                  <td class="py-3 pr-3">{recurso.cantidad_disponible} {recurso.unidad}</td>
                  <td class="py-3 pr-3">{recurso.ubicacion}</td>
                  <td class="py-3">{recurso.zona_codigo}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <section class="grid gap-8 lg:grid-cols-3">
          <div class="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
            <h2 class="text-xl font-semibold">Registrar entrada</h2>
            <form :if={@session_id} phx-submit="ingresar" class="mt-5 grid gap-3">
              <label class="grid gap-1 text-sm font-medium">Código del recurso
                <input name="ingreso[recurso_codigo]" required class="rounded-lg border border-slate-300 p-2" />
              </label>
              <label class="grid gap-1 text-sm font-medium">Cantidad recibida
                <input name="ingreso[cantidad]" type="number" min="1" required class="rounded-lg border border-slate-300 p-2" />
              </label>
              <button type="submit" class="rounded-lg bg-orange-700 px-4 py-2 font-semibold text-white hover:bg-orange-800" phx-disable-with="Guardando...">
                Registrar entrada
              </button>
            </form>
          </div>

          <div class="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
            <h2 class="text-xl font-semibold">Transferir inventario</h2>
            <form :if={@session_id} phx-submit="transferir" class="mt-5 grid gap-3">
              <label class="grid gap-1 text-sm font-medium">Código del recurso
                <input name="transferencia[recurso_codigo]" required class="rounded-lg border border-slate-300 p-2" />
              </label>
              <label class="grid gap-1 text-sm font-medium">Origen
                <input name="transferencia[origen]" required class="rounded-lg border border-slate-300 p-2" />
              </label>
              <label class="grid gap-1 text-sm font-medium">Destino
                <input name="transferencia[destino]" required class="rounded-lg border border-slate-300 p-2" />
              </label>
              <label class="grid gap-1 text-sm font-medium">Cantidad
                <input name="transferencia[cantidad]" type="number" min="1" required class="rounded-lg border border-slate-300 p-2" />
              </label>
              <button type="submit" class="rounded-lg bg-orange-700 px-4 py-2 font-semibold text-white hover:bg-orange-800" phx-disable-with="Transfiriendo...">
                Transferir
              </button>
            </form>
          </div>

          <div class="rounded-xl border border-slate-200 bg-white p-6 shadow-sm lg:col-span-1">
            <h2 class="text-xl font-semibold">Historial de movimientos</h2>
            <div :if={@movimientos == []} class="mt-5 rounded-lg bg-slate-50 p-4 text-sm text-slate-600">
              No hay movimientos registrados.
            </div>
            <ul :if={@movimientos != []} class="mt-4 divide-y divide-slate-100">
              <li :for={movimiento <- @movimientos} class="py-3 text-sm">
                <div class="flex flex-wrap justify-between gap-2">
                  <span class="font-semibold">{movimiento.recurso_codigo} · {movimiento.cantidad}</span>
                  <time class="text-slate-500">{fecha(movimiento.fecha)}</time>
                </div>
                <p class="mt-1 text-slate-600">{movimiento.origen} → {movimiento.destino}</p>
              </li>
            </ul>
          </div>
        </section>
      </div>
    </main>
    """
  end
end
