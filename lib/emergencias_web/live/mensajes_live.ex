defmodule EmergenciasWeb.MensajesLive do
  @moduledoc "Consulta, creación y entrega de mensajes familiares mediante la API existente."
  use EmergenciasWeb, :live_view
  import EmergenciasWeb.MafeComponents
  alias Emergencias.API

  @impl true
  def mount(_params, session, socket) do
    socket =
      assign(socket,
        session_id: session["session_id"],
        usuario: nil,
        personas: [],
        mensajes: [],
        lista_disponible: false,
        error: nil,
        mensaje: nil,
        registro: registro_vacio(),
        filtros: %{"persona_id" => "", "estado" => ""}
      )

    {:ok, cargar_sesion(socket)}
  end

  @impl true
  def handle_event("editar_registro", %{"mensaje" => attrs}, socket),
    do: {:noreply, assign(socket, registro: attrs)}

  def handle_event("crear", %{"mensaje" => attrs}, socket) do
    socket = assign(socket, registro: attrs, mensaje: nil)

    case API.ejecutar(
           socket.assigns.session_id,
           {:enviar_mensaje_familiar, attrs["persona_id"], attrs}
         ) do
      {:ok, _mensaje} ->
        {:noreply,
         socket
         |> assign(
           registro: registro_vacio(),
           mensaje: "Mensaje creado como pendiente.",
           error: nil
         )
         |> cargar_mensajes()}

      {:error, motivo} ->
        {:noreply, fallar(socket, motivo)}
    end
  end

  def handle_event("filtrar", %{"filtros" => filtros}, socket),
    do: {:noreply, socket |> assign(filtros: filtros, mensaje: nil) |> cargar_mensajes()}

  def handle_event("limpiar", _params, socket),
    do:
      {:noreply,
       socket
       |> assign(filtros: %{"persona_id" => "", "estado" => ""}, mensaje: nil)
       |> cargar_mensajes()}

  def handle_event("entregar", %{"id" => id}, socket) do
    case API.ejecutar(socket.assigns.session_id, {:marcar_mensaje_entregado, id}) do
      {:ok, _mensaje} ->
        {:noreply,
         socket
         |> assign(mensaje: "Entrega del mensaje confirmada.", error: nil)
         |> cargar_mensajes()}

      {:error, motivo} ->
        {:noreply, fallar(socket, motivo)}
    end
  end

  def handle_event("reintentar", _params, socket), do: {:noreply, cargar_sesion(socket)}

  defp cargar_sesion(%{assigns: %{session_id: nil}} = socket), do: socket

  defp cargar_sesion(socket) do
    with {:ok, usuario} <- API.consultar(socket.assigns.session_id, :sesion_actual),
         {:ok, personas} <- API.consultar(socket.assigns.session_id, {:personas, %{}}) do
      socket |> assign(usuario: usuario, personas: personas, error: nil) |> cargar_mensajes()
    else
      {:error, motivo} -> fallar(socket, motivo)
    end
  end

  defp cargar_mensajes(socket) do
    case API.consultar(socket.assigns.session_id, {:mensajes_familiares, socket.assigns.filtros}) do
      {:ok, mensajes} ->
        assign(socket, mensajes: mensajes, lista_disponible: true, error: nil)

      {:error, motivo} ->
        socket |> assign(mensajes: [], lista_disponible: false) |> fallar(motivo)
    end
  end

  defp fallar(socket, :sesion_invalida) do
    assign(socket,
      usuario: nil,
      personas: [],
      mensajes: [],
      lista_disponible: false,
      error: mensaje_error(:sesion_invalida),
      mensaje: nil
    )
  end

  defp fallar(socket, :ya_resuelto),
    do:
      assign(socket,
        error: "El mensaje ya fue entregado. No puede entregarse nuevamente.",
        mensaje: nil
      )

  defp fallar(socket, :no_autorizado),
    do: assign(socket, error: "Tu rol o zona no permite gestionar este mensaje.", mensaje: nil)

  defp fallar(socket, motivo), do: assign(socket, error: mensaje_error(motivo), mensaje: nil)

  defp registro_vacio,
    do: %{"persona_id" => "", "remitente" => "", "destinatario" => "", "contenido" => ""}

  defp puede_entregar?(%{rol: rol}) when rol in [:voluntario, :coordinador, :administrador],
    do: true

  defp puede_entregar?(_usuario), do: false
  defp fecha(%DateTime{} = fecha), do: Calendar.strftime(fecha, "%d/%m/%Y %H:%M:%S UTC")

  defp nombre_persona(personas, id) do
    case Enum.find(personas, &(&1.id == id)) do
      nil -> id
      persona -> persona.nombre
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.modulo
      seccion={:mensajes}
      titulo="Mensajes familiares"
      descripcion="Comunicación y seguimiento de mensajes dirigidos a personas afectadas."
      current_user={@current_user}
      csrf_token={@csrf_token}
    >
      <p :if={@mensaje} role="status" class="rounded-lg bg-emerald-100 p-3 text-emerald-900">
        {@mensaje}
      </p>

      <p :if={@error} role="alert" class="rounded-lg bg-rose-100 p-3 text-rose-900">{@error}</p>

      <.tarjeta :if={is_nil(@usuario)} id="acceso-restringido" titulo="Acceso restringido">
        <p class="text-sm text-slate-600">
          Necesitas una sesión activa para consultar y crear mensajes familiares.
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

        <.tarjeta id="filtros-mensajes" titulo="Consultar mensajes">
          <p :if={@usuario.rol == :ciudadano} class="mb-4 text-sm text-slate-600">
            Puedes consultar los mensajes que hayas creado dentro de tu zona.
          </p>

          <.form
            for={to_form(@filtros, as: :filtros)}
            id="filtrar-mensajes"
            phx-submit="filtrar"
            class="grid gap-4 sm:grid-cols-3"
          >
            <label class="grid gap-1 text-sm font-medium">
              Persona
              <select name="filtros[persona_id]" class="rounded-lg border border-slate-300 p-2">
                <option value="">Todas las personas permitidas</option>

                <option
                  :for={persona <- @personas}
                  value={persona.id}
                  selected={@filtros["persona_id"] == persona.id}
                >
                  {persona.nombre} · {persona.id}
                </option>
              </select>
            </label>

            <label class="grid gap-1 text-sm font-medium">
              Estado
              <select name="filtros[estado]" class="rounded-lg border border-slate-300 p-2">
                <option value="">Todos los estados</option>

                <option value="pendiente" selected={@filtros["estado"] == "pendiente"}>
                  Pendiente
                </option>

                <option value="entregado" selected={@filtros["estado"] == "entregado"}>
                  Entregado
                </option>
              </select>
            </label>

            <button
              class="self-end rounded-lg bg-orange-700 px-4 py-2 font-semibold text-white hover:bg-orange-800"
              phx-disable-with="Filtrando..."
            >Aplicar filtros</button>
          </.form>

          <button type="button" phx-click="limpiar" class="mt-3 text-sm font-semibold text-orange-700">Mostrar todos los mensajes permitidos</button>
        </.tarjeta>

        <.tarjeta id="registro-mensajes" titulo="Crear mensaje familiar">
          <p :if={@personas == []} class="text-sm text-slate-600">
            No hay personas disponibles para asociar un mensaje.
            <a href="/personas" class="font-semibold text-orange-700">Consultar personas afectadas →</a>
          </p>

          <.form
            :if={@personas != []}
            for={to_form(@registro, as: :mensaje)}
            id="crear-mensaje"
            phx-change="editar_registro"
            phx-submit="crear"
            class="grid gap-4 md:grid-cols-2"
          >
            <label class="grid gap-1 text-sm font-medium md:col-span-2">
              Persona afectada
              <select
                name="mensaje[persona_id]"
                required
                class="rounded-lg border border-slate-300 p-2"
              >
                <option value="">Selecciona una persona</option>

                <option
                  :for={persona <- @personas}
                  value={persona.id}
                  selected={@registro["persona_id"] == persona.id}
                >
                  {persona.nombre} · {persona.id}
                </option>
              </select>
            </label>

            <label class="grid gap-1 text-sm font-medium">
              Remitente
              <input
                name="mensaje[remitente]"
                value={@registro["remitente"]}
                required
                class="rounded-lg border border-slate-300 p-2"
              />
            </label>

            <label class="grid gap-1 text-sm font-medium">
              Destinatario
              <input
                name="mensaje[destinatario]"
                value={@registro["destinatario"]}
                required
                class="rounded-lg border border-slate-300 p-2"
              />
            </label>

            <label class="grid gap-1 text-sm font-medium md:col-span-2">
              Contenido <textarea
                name="mensaje[contenido]"
                required
                rows="4"
                class="rounded-lg border border-slate-300 p-2"
              >{@registro["contenido"]}</textarea>
            </label>

            <p class="text-sm text-slate-600 md:col-span-2">
              Remitente y destinatario son datos informativos. La entrega se confirma por personal autorizado.
            </p>

            <div class="md:col-span-2">
              <button
                class="rounded-lg bg-orange-700 px-4 py-2 font-semibold text-white hover:bg-orange-800"
                phx-disable-with="Guardando..."
              >Crear mensaje</button>
            </div>
          </.form>
        </.tarjeta>

        <.tarjeta id="listado-mensajes" titulo="Mensajes registrados">
          <p :if={!@lista_disponible} class="text-sm text-slate-600">
            No se pudo cargar el listado. Revisa el mensaje de error e intenta nuevamente.
          </p>

          <p :if={@lista_disponible && @mensajes == []} class="text-sm text-slate-600">
            No hay mensajes para mostrar con estos filtros.
          </p>

          <div :if={@lista_disponible} class="space-y-4">
            <article
              :for={mensaje <- @mensajes}
              id={"mensaje-#{mensaje.id}"}
              class="rounded-lg border border-slate-200 p-4"
            >
              <div class="flex flex-wrap items-center justify-between gap-3">
                <h3 class="font-semibold">{nombre_persona(@personas, mensaje.persona_id)}</h3>

                <span class={
                  if mensaje.estado == :entregado,
                    do: "rounded-full bg-emerald-100 px-3 py-1 text-sm text-emerald-800",
                    else: "rounded-full bg-slate-100 px-3 py-1 text-sm text-slate-700"
                }>{if mensaje.estado == :entregado, do: "Entregado", else: "Pendiente"}</span>
              </div>

              <dl class="mt-3 grid gap-3 text-sm sm:grid-cols-2">
                <div>
                  <dt class="text-slate-500">Remitente</dt><dd class="break-words">
                    {mensaje.remitente}
                  </dd>
                </div>

                <div>
                  <dt class="text-slate-500">Destinatario</dt><dd class="break-words">
                    {mensaje.destinatario}
                  </dd>
                </div>

                <div>
                  <dt class="text-slate-500">Fecha de creación</dt><dd>{fecha(mensaje.fecha)}</dd>
                </div>

                <div>
                  <dt class="text-slate-500">Identificador</dt><dd class="break-all">{mensaje.id}</dd>
                </div>
              </dl>

              <p class="mt-4 whitespace-pre-wrap break-words text-sm text-slate-700">
                {mensaje.contenido}
              </p>

              <button
                :if={mensaje.estado == :pendiente && puede_entregar?(@usuario)}
                type="button"
                phx-click="entregar"
                phx-value-id={mensaje.id}
                data-confirm="¿Confirmas que este mensaje fue entregado?"
                class="mt-4 rounded-lg bg-orange-700 px-4 py-2 text-sm font-semibold text-white hover:bg-orange-800"
                phx-disable-with="Confirmando..."
              >Marcar como entregado</button>
            </article>
          </div>
        </.tarjeta>
      </div>
    </.modulo>
    """
  end
end
