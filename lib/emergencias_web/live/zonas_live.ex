defmodule EmergenciasWeb.ZonasLive do
  @moduledoc "Interfaz de demostración para administración territorial y estadísticas."
  use EmergenciasWeb, :live_view

  alias Emergencias.{API, Codigos, PuntoAtencion, Zona, Zonas}
  alias EmergenciasWeb.AppShell
  alias EmergenciasWeb.LiveAuth

  @niveles [:baja, :media, :alta, :critica]
  @estados [:activo, :inactivo, :saturado]

  @impl true
  def mount(_params, session, socket) do
    zonas = cargar_zonas(session["session_id"])

    {:ok,
     assign(socket,
       session_id: session["session_id"],
       zonas: zonas,
       errores: %{},
       opciones_zona: opciones_zona(zonas),
       mensaje: nil,
       tipo_mensaje: "info",
       niveles: Enum.map(@niveles, &{humanizar(&1), Atom.to_string(&1)}),
       estados: Enum.map(@estados, &{humanizar(&1), Atom.to_string(&1)})
     )}
  end

  @impl true
  def handle_event("validar_zona", %{"zona" => attrs}, socket) do
    error = error_codigo(:zona, attrs["codigo"])
    {:noreply, assign(socket, errores: Map.put(socket.assigns.errores, :zona, error))}
  end

  def handle_event("validar_sector", %{"sector" => attrs}, socket) do
    error = error_codigo(:sector, attrs["codigo"])
    {:noreply, assign(socket, errores: Map.put(socket.assigns.errores, :sector, error))}
  end

  def handle_event("validar_punto", %{"punto" => attrs}, socket) do
    errores =
      socket.assigns.errores
      |> Map.put(:sector_punto, error_codigo(:sector, attrs["sector_codigo"]))
      |> Map.put(:punto, error_codigo(:punto_atencion, attrs["codigo"]))

    {:noreply, assign(socket, errores: errores)}
  end

  def handle_event("crear_zona", %{"zona" => attrs}, socket) do
    case API.ejecutar(socket.assigns.session_id, {:registrar_zona, attrs}) do
      {:ok, _zona} ->
        zonas = cargar_zonas(socket.assigns.session_id)

        {:noreply,
         socket
         |> assign(zonas: zonas, opciones_zona: opciones_zona(zonas), errores: %{})
         |> feedback("Zona creada.", "success")}

      {:error, motivo} ->
        {:noreply, mostrar_error(socket, motivo)}
    end
  end

  def handle_event("agregar_sector", %{"sector" => attrs}, socket) do
    case API.ejecutar(
           socket.assigns.session_id,
           {:registrar_sector, attrs["zona_codigo"], attrs}
         ) do
      {:ok, _sector} ->
        zonas = cargar_zonas(socket.assigns.session_id)

        {:noreply,
         socket
         |> assign(zonas: zonas, errores: %{})
         |> feedback("Sector agregado a la zona.", "success")}

      {:error, motivo} ->
        {:noreply, mostrar_error(socket, motivo)}
    end
  end

  def handle_event("agregar_punto", %{"punto" => attrs}, socket) do
    case API.ejecutar(
           socket.assigns.session_id,
           {:registrar_punto_atencion, attrs["zona_codigo"], attrs["sector_codigo"], attrs}
         ) do
      {:ok, _punto} ->
        zonas = cargar_zonas(socket.assigns.session_id)

        {:noreply,
         socket
         |> assign(zonas: zonas, errores: %{})
         |> feedback("Punto agregado al sector.", "success")}

      {:error, motivo} ->
        {:noreply, mostrar_error(socket, motivo)}
    end
  end

  def handle_event(
        "alternar_punto",
        %{"zona" => zona_codigo, "sector" => sector_codigo, "punto" => punto_codigo},
        socket
      ) do
    with %Zona{sectores: sectores} <- Map.get(socket.assigns.zonas, zona_codigo),
         %PuntoAtencion{} = punto <- Zonas.buscar_punto(sectores, punto_codigo) do
      estado = if punto.estado == :activo, do: :inactivo, else: :activo

      case API.ejecutar(
             socket.assigns.session_id,
             {:cambiar_estado_punto_atencion, zona_codigo, sector_codigo, punto_codigo, estado}
           ) do
        {:ok, _resultado} ->
          zonas = cargar_zonas(socket.assigns.session_id)

          {:noreply,
           socket |> assign(zonas: zonas) |> feedback("Estado del punto actualizado.", "success")}

        {:error, motivo} ->
          {:noreply, mostrar_error(socket, motivo)}
      end
    else
      _resultado -> {:noreply, mostrar_error(socket, :no_encontrado)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell
      title="Zonas"
      current_path="/zonas"
      current_user={@current_user}
      csrf_token={@csrf_token}
      flash={@flash}
    >
      <div class="mt-6">
        <p class="text-sm font-semibold uppercase tracking-widest text-orange-700">
          Organización territorial
        </p>

        <div class="mt-1 flex flex-wrap items-end justify-between gap-3">
          <div>
            <h1 class="text-3xl font-black">Zonas y puntos de atención</h1>

            <p class="mt-2 text-slate-600">
              Organiza el territorio afectado y consulta sus indicadores recursivos.
            </p>
          </div>

          <span class="rounded-xl border border-slate-200 bg-white px-4 py-3 text-sm"><strong class="text-lg">{map_size(
            zonas_visibles(@zonas, @current_user)
          )}</strong><span class="ml-2 text-slate-500">zonas en tu alcance</span></span>
        </div>
      </div>
      <AppShell.notice message={@mensaje} kind={@tipo_mensaje} />
      <AppShell.notice
        :if={!LiveAuth.administrador?(@current_user)}
        message="Vista de consulta. Solo un administrador puede crear zonas, sectores, puntos o cambiar su estado."
      />
      <div :if={LiveAuth.administrador?(@current_user)} class="mt-6 grid gap-5 xl:grid-cols-3">
        <AppShell.panel
          title="Nueva zona"
          description="Define el nivel de afectación y la población estimada."
        >
          <.form
            for={%{}}
            as={:zona}
            phx-change="validar_zona"
            phx-submit="crear_zona"
            class="space-y-3"
          >
            <AppShell.field
              label="Código"
              name="zona[codigo]"
              placeholder="Z-03"
              pattern="Z-[0-9]{2}"
              title="Usa el formato Z-01."
              hint={Codigos.formato(:zona)}
              error={@errores[:zona]}
              required
            />
            <AppShell.field
              label="Nombre"
              name="zona[nombre]"
              placeholder="Nombre de la zona"
              required
            />
            <AppShell.select_field
              label="Afectación"
              name="zona[nivel_afectacion]"
              options={@niveles}
              value="media"
            />
            <AppShell.field
              label="Personas estimadas"
              name="zona[personas_estimadas]"
              type="number"
              min="0"
              value="0"
              required
            />
            <button class="w-full rounded-lg bg-orange-600 px-4 py-2.5 font-semibold text-white hover:bg-orange-500">Crear zona</button>
          </.form>
        </AppShell.panel>

        <AppShell.panel title="Agregar sector" description="El sector se agrega a una zona existente.">
          <.form
            for={%{}}
            as={:sector}
            phx-change="validar_sector"
            phx-submit="agregar_sector"
            class="space-y-3"
          >
            <AppShell.select_field
              label="Código de zona"
              name="sector[zona_codigo]"
              options={@opciones_zona}
              value={zona_predeterminada(@opciones_zona)}
              required
            />
            <AppShell.field
              label="Código del sector"
              name="sector[codigo]"
              placeholder="SEC-03"
              pattern="SEC-[0-9]{2}"
              title="Usa el formato SEC-01."
              hint={Codigos.formato(:sector)}
              error={@errores[:sector]}
              required
            />
            <AppShell.field
              label="Nombre"
              name="sector[nombre]"
              placeholder="Sector Oriente"
              required
            />
            <button class="w-full rounded-lg bg-slate-900 px-4 py-2.5 font-semibold text-white hover:bg-slate-700">Agregar sector</button>
          </.form>
        </AppShell.panel>

        <AppShell.panel title="Agregar punto" description="Asocia el punto con su zona y su sector.">
          <.form
            for={%{}}
            as={:punto}
            phx-change="validar_punto"
            phx-submit="agregar_punto"
            class="space-y-3"
          >
            <AppShell.select_field
              label="Código de zona"
              name="punto[zona_codigo]"
              options={@opciones_zona}
              value={zona_predeterminada(@opciones_zona)}
              required
            />
            <AppShell.field
              label="Código de sector"
              name="punto[sector_codigo]"
              placeholder="SEC-01"
              pattern="SEC-[0-9]{2}"
              title="Usa el formato SEC-01."
              hint={Codigos.formato(:sector)}
              error={@errores[:sector_punto]}
              required
            />
            <div class="grid grid-cols-2 gap-3">
              <AppShell.field
                label="Código del punto"
                name="punto[codigo]"
                placeholder="PA-03"
                pattern="PA-[0-9]{2}"
                title="Usa el formato PA-01."
                hint={Codigos.formato(:punto_atencion)}
                error={@errores[:punto]}
                required
              />
              <AppShell.field
                label="Personas"
                name="punto[personas_estimadas]"
                type="number"
                min="0"
                value="0"
                required
              />
            </div>

            <AppShell.field
              label="Nombre del punto"
              name="punto[nombre]"
              placeholder="Puesto de salud"
              required
            />
            <AppShell.select_field
              label="Estado inicial"
              name="punto[estado]"
              options={@estados}
              value="activo"
            />
            <button class="w-full rounded-lg bg-slate-900 px-4 py-2.5 font-semibold text-white hover:bg-slate-700">Agregar punto</button>
          </.form>
        </AppShell.panel>
      </div>

      <div class="mt-7 space-y-5">
        <AppShell.panel
          :for={
            zona <- zonas_visibles(@zonas, @current_user) |> Map.values() |> Enum.sort_by(& &1.codigo)
          }
          title={"#{zona.codigo} · #{zona.nombre}"}
          description={"Afectación #{humanizar(zona.nivel_afectacion)} · #{zona.personas_estimadas} personas estimadas"}
        >
          <div class="mb-5 grid gap-3 sm:grid-cols-3">
            <.metric label="Sectores" value={Zonas.contar_sectores(zona)} />
            <.metric label="Puntos registrados" value={Zonas.contar_puntos(zona)} />
            <.metric label="Puntos activos" value={Zonas.contar_puntos_por_estado(zona, :activo)} />
          </div>

          <div :if={zona.sectores == []} class="rounded-lg bg-slate-50 p-4 text-sm text-slate-500">
            Esta zona aún no tiene sectores.
          </div>

          <div
            :for={sector <- zona.sectores}
            class="mb-3 rounded-xl border border-slate-200 p-4 last:mb-0"
          >
            <div class="flex flex-wrap items-center justify-between gap-2">
              <h3 class="font-bold">{sector.codigo} · {sector.nombre}</h3>
              <span class="text-xs text-slate-500">{length(sector.puntos)} puntos</span>
            </div>

            <div :if={sector.puntos == []} class="mt-3 text-sm text-slate-500">
              Sin puntos de atención.
            </div>

            <div
              :for={punto <- sector.puntos}
              class="mt-3 flex flex-wrap items-center justify-between gap-3 rounded-lg bg-slate-50 px-3 py-3"
            >
              <div>
                <p class="text-sm font-semibold">{punto.codigo} · {punto.nombre}</p>

                <p class="mt-0.5 text-xs text-slate-500">
                  {punto.personas_estimadas} personas estimadas
                </p>
              </div>

              <div class="flex items-center gap-2">
                <span class={estado_badge(punto.estado)}>{humanizar(punto.estado)}</span>
                <button
                  :if={LiveAuth.administrador?(@current_user)}
                  type="button"
                  phx-click="alternar_punto"
                  phx-value-zona={zona.codigo}
                  phx-value-sector={sector.codigo}
                  phx-value-punto={punto.codigo}
                  class="rounded-md border border-slate-300 bg-white px-2.5 py-1.5 text-xs font-semibold hover:bg-slate-100"
                >
                  {if punto.estado == :activo, do: "Desactivar", else: "Activar"}
                </button>
              </div>
            </div>
          </div>
        </AppShell.panel>
      </div>
    </AppShell.shell>
    """
  end

  defp metric(assigns) do
    ~H"""
    <div class="rounded-xl bg-slate-50 p-4">
      <p class="text-xs font-semibold uppercase tracking-wide text-slate-500">{@label}</p>

      <p class="mt-1 text-2xl font-black">{@value}</p>
    </div>
    """
  end

  defp mostrar_error(socket, :id_duplicado),
    do: feedback(socket, "Ese código ya está registrado.", "error")

  defp mostrar_error(socket, :no_encontrado),
    do: feedback(socket, "No se encontró la zona o el sector indicado.", "error")

  defp mostrar_error(socket, motivo),
    do: feedback(socket, "No se pudo guardar: #{humanizar(motivo)}.", "error")

  defp feedback(socket, mensaje, tipo), do: assign(socket, mensaje: mensaje, tipo_mensaje: tipo)

  defp humanizar(value) when is_atom(value),
    do: value |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()

  defp humanizar(value), do: to_string(value)

  defp estado_badge(:activo),
    do: "rounded-full bg-emerald-100 px-2.5 py-1 text-xs font-semibold text-emerald-800"

  defp estado_badge(:saturado),
    do: "rounded-full bg-amber-100 px-2.5 py-1 text-xs font-semibold text-amber-800"

  defp estado_badge(_estado),
    do: "rounded-full bg-slate-200 px-2.5 py-1 text-xs font-semibold text-slate-700"

  defp error_codigo(_tipo, nil), do: nil
  defp error_codigo(_tipo, ""), do: nil

  defp error_codigo(tipo, codigo) do
    if Codigos.valido?(tipo, codigo),
      do: nil,
      else: "Formato inválido. Ejemplo: #{Codigos.formato(tipo)}."
  end

  defp opciones_zona(zonas) do
    zonas
    |> Map.values()
    |> Enum.sort_by(& &1.codigo)
    |> Enum.map(&{"#{&1.nombre} · #{&1.codigo}", &1.codigo})
  end

  defp cargar_zonas(session_id) do
    case API.consultar(session_id, :zonas) do
      {:ok, zonas} -> Map.new(zonas, &{&1.codigo, &1})
      {:error, _motivo} -> %{}
    end
  end

  defp zonas_visibles(zonas, %{rol: :administrador}), do: zonas

  defp zonas_visibles(zonas, usuario),
    do: Map.take(zonas, [usuario.zona_principal])

  defp zona_predeterminada([{_nombre, codigo} | _resto]), do: codigo
  defp zona_predeterminada([]), do: ""
end
