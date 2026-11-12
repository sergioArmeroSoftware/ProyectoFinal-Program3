defmodule EmergenciasWeb.PersonasLive do
  @moduledoc "Registro, búsqueda y seguimiento de personas mediante la API del sistema."
  use EmergenciasWeb, :live_view
  import EmergenciasWeb.MafeComponents
  alias Emergencias.API

  @estados [:sin_informacion, :reportada, :localizada, :trasladada, :en_albergue, :reunificada]

  @impl true
  def mount(_params, session, socket) do
    socket =
      assign(socket,
        session_id: session["session_id"],
        usuario: nil,
        personas: [],
        zonas: [],
        detalle: nil,
        historial: [],
        error: nil,
        mensaje: nil,
        lista_disponible: false,
        registro: registro_vacio(),
        filtros: %{"zona_codigo" => "", "estado" => ""},
        documento: "",
        cambio: %{"estado" => ""},
        estados: @estados
      )

    {:ok, cargar_sesion(socket)}
  end

  @impl true
  def handle_event("editar_registro", %{"persona" => attrs}, socket),
    do: {:noreply, assign(socket, registro: attrs)}

  def handle_event("registrar", %{"persona" => attrs}, socket) do
    socket = assign(socket, registro: attrs, mensaje: nil)

    case API.ejecutar(socket.assigns.session_id, {:reportar_persona, attrs}) do
      {:ok, persona} ->
        socket =
          assign(socket, registro: registro_vacio(), mensaje: "Persona registrada.", error: nil)

        {:noreply, socket |> cargar_personas() |> cargar_detalle(persona.id)}

      {:error, motivo} ->
        {:noreply, fallar(socket, motivo)}
    end
  end

  def handle_event("buscar", %{"busqueda" => %{"documento" => documento}}, socket) do
    {:noreply,
     socket
     |> assign(documento: documento, mensaje: nil, detalle: nil, historial: [])
     |> cargar_personas()}
  end

  def handle_event("filtrar", %{"filtros" => filtros}, socket) do
    {:noreply,
     socket
     |> assign(filtros: filtros, documento: "", mensaje: nil, detalle: nil, historial: [])
     |> cargar_personas()}
  end

  def handle_event("limpiar", _params, socket) do
    {:noreply,
     socket
     |> assign(documento: "", filtros: %{"zona_codigo" => "", "estado" => ""}, mensaje: nil)
     |> cargar_personas()}
  end

  def handle_event("detalle", %{"id" => id}, socket),
    do: {:noreply, socket |> assign(mensaje: nil) |> cargar_detalle(id)}

  def handle_event("editar_estado", %{"cambio" => attrs}, socket),
    do: {:noreply, assign(socket, cambio: attrs)}

  def handle_event("cambiar_estado", %{"cambio" => attrs}, socket) do
    socket = assign(socket, cambio: attrs, mensaje: nil)

    case socket.assigns.detalle do
      nil ->
        {:noreply, fallar(socket, :no_encontrado)}

      persona ->
        case API.ejecutar(
               socket.assigns.session_id,
               {:cambiar_estado_persona, persona.id, attrs["estado"]}
             ) do
          {:ok, _persona} ->
            socket =
              assign(socket, mensaje: "Estado actualizado e historial registrado.", error: nil)

            {:noreply, socket |> cargar_personas() |> cargar_detalle(persona.id)}

          {:error, motivo} ->
            {:noreply, fallar(socket, motivo)}
        end
    end
  end

  def handle_event("reintentar", _params, socket), do: {:noreply, cargar_sesion(socket)}

  defp cargar_sesion(%{assigns: %{session_id: nil}} = socket), do: socket

  defp cargar_sesion(socket) do
    with {:ok, usuario} <- API.consultar(socket.assigns.session_id, :sesion_actual),
         {:ok, zonas} <- API.consultar(socket.assigns.session_id, :zonas) do
      socket |> assign(usuario: usuario, zonas: zonas, error: nil) |> cargar_personas()
    else
      {:error, motivo} -> fallar(socket, motivo)
    end
  end

  defp cargar_personas(socket) do
    consulta =
      if String.trim(socket.assigns.documento) == "",
        do: {:personas, socket.assigns.filtros},
        else: {:personas_por_documento, socket.assigns.documento}

    case API.consultar(socket.assigns.session_id, consulta) do
      {:ok, personas} ->
        assign(socket, personas: personas, lista_disponible: true, error: nil)

      {:error, motivo} ->
        socket |> assign(personas: [], lista_disponible: false) |> fallar(motivo)
    end
  end

  defp cargar_detalle(socket, id) do
    with {:ok, persona} <- API.consultar(socket.assigns.session_id, {:persona, id}),
         {:ok, historial} <- API.consultar(socket.assigns.session_id, {:historial_persona, id}) do
      assign(socket,
        detalle: persona,
        historial: historial,
        cambio: %{"estado" => ""},
        error: nil
      )
    else
      {:error, motivo} -> socket |> assign(detalle: nil, historial: []) |> fallar(motivo)
    end
  end

  defp fallar(socket, :sesion_invalida) do
    assign(socket,
      usuario: nil,
      personas: [],
      zonas: [],
      detalle: nil,
      historial: [],
      lista_disponible: false,
      error: mensaje_error(:sesion_invalida),
      mensaje: nil
    )
  end

  defp fallar(socket, motivo), do: assign(socket, error: mensaje_error(motivo), mensaje: nil)

  defp registro_vacio,
    do: %{
      "nombre" => "",
      "documento_referencia" => "",
      "edad" => "",
      "zona_codigo" => "",
      "estado" => "reportada"
    }

  defp fecha(%DateTime{} = fecha), do: Calendar.strftime(fecha, "%d/%m/%Y %H:%M:%S UTC")

  @impl true
  def render(assigns) do
    ~H"""
    <.modulo
      titulo="Personas afectadas"
      descripcion="Registro, búsqueda y seguimiento de personas afectadas por la emergencia."
    >
      <p :if={@mensaje} role="status" class="rounded-lg bg-emerald-100 p-3 text-emerald-900">
        {@mensaje}
      </p>
      <p :if={@error} role="alert" class="rounded-lg bg-rose-100 p-3 text-rose-900">{@error}</p>

      <.tarjeta :if={is_nil(@usuario)} id="acceso-restringido" titulo="Acceso restringido">
        <p class="text-sm text-slate-600">
          Necesitas una sesión activa para consultar y registrar personas.
        </p>
        <p class="mt-2 text-sm text-slate-600">
          El inicio de sesión web está pendiente de integración en Usuarios y permisos.
        </p>
        <a href="/usuarios" class="mt-4 inline-block text-sm font-semibold text-orange-700">Usuarios y permisos →</a>
        <button
          :if={@session_id}
          type="button"
          phx-click="reintentar"
          class="ml-4 rounded-lg border border-slate-300 px-4 py-2 text-sm font-semibold"
        >Reintentar</button>
      </.tarjeta>

      <div :if={@usuario} class="space-y-6">
        <p class="text-sm text-slate-600">
          Sesión: {@usuario.nombre_completo} · {if @usuario.rol == :administrador,
            do: "Alcance global",
            else: "Zona #{@usuario.zona_principal}"}
        </p>
        <.tarjeta id="busqueda-personas" titulo="Buscar personas">
          <.form
            for={to_form(%{"documento" => @documento}, as: :busqueda)}
            id="buscar-personas"
            phx-submit="buscar"
            class="grid gap-4 sm:grid-cols-[1fr_auto]"
          >
            <label class="grid gap-1 text-sm font-medium">
              Documento de referencia
              <input
                name="busqueda[documento]"
                value={@documento}
                class="rounded-lg border border-slate-300 p-2"
              />
            </label>
            <button
              class="self-end rounded-lg bg-orange-700 px-4 py-2 font-semibold text-white hover:bg-orange-800"
              phx-disable-with="Buscando..."
            >Buscar</button>
          </.form>
          <.form
            for={to_form(@filtros, as: :filtros)}
            id="filtrar-personas"
            phx-submit="filtrar"
            class="mt-5 grid gap-4 sm:grid-cols-3"
          >
            <label class="grid gap-1 text-sm font-medium">
              Zona
              <select name="filtros[zona_codigo]" class="rounded-lg border border-slate-300 p-2">
                <option value="">Todas las zonas permitidas</option>
                <option
                  :for={zona <- @zonas}
                  value={zona.codigo}
                  selected={@filtros["zona_codigo"] == zona.codigo}
                >
                  {zona.nombre || zona.codigo}
                </option>
              </select>
            </label>
            <label class="grid gap-1 text-sm font-medium">
              Estado
              <select name="filtros[estado]" class="rounded-lg border border-slate-300 p-2">
                <option value="">Todos los estados</option>
                <option
                  :for={estado <- @estados}
                  value={estado}
                  selected={@filtros["estado"] == to_string(estado)}
                >
                  {etiqueta_estado(estado)}
                </option>
              </select>
            </label>
            <button
              class="self-end rounded-lg bg-orange-700 px-4 py-2 font-semibold text-white hover:bg-orange-800"
              phx-disable-with="Filtrando..."
            >Aplicar filtros</button>
          </.form>
          <p class="mt-3 text-sm text-slate-600">
            La búsqueda por documento y los filtros se aplican por separado.
          </p>
          <button type="button" phx-click="limpiar" class="mt-3 text-sm font-semibold text-orange-700">Mostrar todas las personas permitidas</button>
        </.tarjeta>

        <.tarjeta id="registro-personas" titulo="Registrar persona">
          <.form
            for={to_form(@registro, as: :persona)}
            id="registrar-persona"
            phx-change="editar_registro"
            phx-submit="registrar"
            class="grid gap-4 md:grid-cols-2"
          >
            <label class="grid gap-1 text-sm font-medium">
              Nombre
              <input
                name="persona[nombre]"
                value={@registro["nombre"]}
                required
                class="rounded-lg border border-slate-300 p-2"
              />
            </label>
            <label class="grid gap-1 text-sm font-medium">
              Documento de referencia (opcional)
              <input
                name="persona[documento_referencia]"
                value={@registro["documento_referencia"]}
                class="rounded-lg border border-slate-300 p-2"
              />
            </label>
            <label class="grid gap-1 text-sm font-medium">
              Edad
              <input
                name="persona[edad]"
                value={@registro["edad"]}
                type="number"
                min="0"
                step="1"
                required
                class="rounded-lg border border-slate-300 p-2"
              />
            </label>
            <label class="grid gap-1 text-sm font-medium">
              Zona
              <select
                name="persona[zona_codigo]"
                required
                class="rounded-lg border border-slate-300 p-2"
              >
                <option value="">Selecciona una zona</option>
                <option
                  :for={zona <- @zonas}
                  value={zona.codigo}
                  selected={@registro["zona_codigo"] == zona.codigo}
                >
                  {zona.nombre || zona.codigo}
                </option>
              </select>
            </label>
            <label class="grid gap-1 text-sm font-medium">
              Estado inicial
              <select name="persona[estado]" class="rounded-lg border border-slate-300 p-2">
                <option
                  :for={estado <- @estados}
                  value={estado}
                  selected={@registro["estado"] == to_string(estado)}
                >
                  {etiqueta_estado(estado)}
                </option>
              </select>
            </label>
            <button
              class="self-end rounded-lg bg-orange-700 px-4 py-2 font-semibold text-white hover:bg-orange-800"
              phx-disable-with="Guardando..."
            >Registrar persona</button>
          </.form>
        </.tarjeta>

        <.tarjeta id="listado-personas" titulo="Personas registradas">
          <p :if={!@lista_disponible} class="text-sm text-slate-600">
            No se pudo cargar el listado. Revisa el mensaje de error e intenta nuevamente.
          </p>
          <p :if={@lista_disponible && @personas == []} class="text-sm text-slate-600">
            No hay personas para mostrar con esta búsqueda.
          </p>
          <div :if={@lista_disponible && @personas != []} class="overflow-x-auto">
            <table class="w-full min-w-[600px] text-left text-sm">
              <thead class="border-b border-slate-200 text-slate-500">
                <tr>
                  <th class="py-3 pr-3">Nombre</th><th class="py-3 pr-3">Documento</th><th class="py-3 pr-3">
                    Zona
                  </th><th class="py-3 pr-3">Estado</th><th class="py-3">Detalle</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={persona <- @personas}
                  id={"persona-#{persona.id}"}
                  class="border-b border-slate-100"
                >
                  <td class="py-4 pr-3">{persona.nombre}</td><td class="py-4 pr-3">
                    {persona.documento_referencia || "Sin referencia"}
                  </td><td class="py-4 pr-3">{persona.zona_codigo}</td>
                  <td class="py-4 pr-3"><.estado_persona estado={persona.estado} /></td>
                  <td class="py-4">
                    <button
                      type="button"
                      phx-click="detalle"
                      phx-value-id={persona.id}
                      class="font-semibold text-orange-700"
                    >Ver detalle</button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </.tarjeta>

        <.tarjeta :if={@detalle} id="detalle-persona" titulo="Detalle e historial">
          <dl class="grid gap-3 text-sm sm:grid-cols-2">
            <div>
              <dt class="text-slate-500">Nombre</dt><dd class="font-semibold">{@detalle.nombre}</dd>
            </div>
            <div>
              <dt class="text-slate-500">Identificador</dt><dd class="break-all">{@detalle.id}</dd>
            </div>
            <div>
              <dt class="text-slate-500">Documento</dt><dd>
                {@detalle.documento_referencia || "Sin referencia"}
              </dd>
            </div>
            <div>
              <dt class="text-slate-500">Edad</dt><dd>{@detalle.edad}</dd>
            </div>
            <div>
              <dt class="text-slate-500">Zona</dt><dd>{@detalle.zona_codigo}</dd>
            </div>
            <div>
              <dt class="mb-1 text-slate-500">Estado actual</dt><dd>
                <.estado_persona estado={@detalle.estado} />
              </dd>
            </div>
          </dl>
          <p :if={@detalle.estado == :reunificada} class="mt-5 text-sm text-slate-600">
            La reunificación es un estado final.
          </p>
          <div :if={@detalle.estado != :reunificada} class="mt-5 border-t border-slate-200 pt-5">
            <p class="mb-3 text-sm text-slate-600">
              El cambio requiere autorización. Si eres ciudadano, solo puedes actualizar reportes cuya autoría pueda comprobarse.
            </p>
            <.form
              for={to_form(@cambio, as: :cambio)}
              id="cambiar-estado-persona"
              phx-change="editar_estado"
              phx-submit="cambiar_estado"
              class="flex flex-wrap items-end gap-3"
            >
              <label class="grid gap-1 text-sm font-medium">
                Nuevo estado
                <select name="cambio[estado]" required class="rounded-lg border border-slate-300 p-2">
                  <option value="">Selecciona</option>
                  <option
                    :for={estado <- @estados}
                    :if={estado != @detalle.estado}
                    value={estado}
                    selected={@cambio["estado"] == to_string(estado)}
                  >
                    {etiqueta_estado(estado)}
                  </option>
                </select>
              </label>
              <button
                class="rounded-lg bg-orange-700 px-4 py-2 font-semibold text-white hover:bg-orange-800"
                phx-disable-with="Guardando..."
                data-confirm="¿Confirmas el cambio de estado de esta persona?"
              >Cambiar estado</button>
            </.form>
          </div>
          <h3 class="mt-6 font-semibold">Historial de cambios</h3>
          <p :if={@historial == []} class="mt-3 text-sm text-slate-600">
            No hay cambios de estado registrados.
          </p>
          <ol id="historial-persona" class="mt-3 space-y-3">
            <li :for={cambio <- @historial} class="rounded-lg bg-slate-50 p-3 text-sm">
              <p>
                {etiqueta_estado(cambio.estado_anterior)} → {etiqueta_estado(cambio.estado_nuevo)}
              </p>
              <p class="mt-1 text-slate-600">{fecha(cambio.fecha)} · Usuario: {cambio.usuario_id}</p>
            </li>
          </ol>
        </.tarjeta>
      </div>
    </.modulo>
    """
  end
end
