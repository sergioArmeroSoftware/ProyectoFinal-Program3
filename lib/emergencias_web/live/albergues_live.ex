defmodule EmergenciasWeb.AlberguesLive do
  @moduledoc "Interfaz de demostración para capacidad y estancias en albergues."
  use EmergenciasWeb, :live_view

  alias Emergencias.{API, Codigos}
  alias EmergenciasWeb.AppShell
  alias EmergenciasWeb.LiveAuth

  @impl true
  def mount(_params, session, socket) do
    session_id = session["session_id"]
    datos = cargar_datos(session_id)

    {:ok,
     assign(socket,
       session_id: session_id,
       albergues: datos.albergues,
       resumenes: datos.resumenes,
       zonas: datos.zonas,
       estancias: datos.estancias,
       personas: datos.personas,
       errores: %{},
       mensaje: nil,
       tipo_mensaje: "info"
     )}
  end

  @impl true
  def handle_event("validar_albergue", %{"albergue" => attrs}, socket) do
    error = error_codigo(:albergue, attrs["codigo"])
    {:noreply, assign(socket, errores: Map.put(socket.assigns.errores, :albergue, error))}
  end

  def handle_event("registrar_albergue", %{"albergue" => attrs}, socket) do
    case Integer.parse(attrs["capacidad_maxima"] || "") do
      {capacidad, ""} when capacidad >= 0 ->
        attrs = Map.put(attrs, "capacidad_maxima", capacidad)

        case API.ejecutar(socket.assigns.session_id, {:registrar_albergue, attrs}) do
          {:ok, _albergue} ->
            datos = cargar_datos(socket.assigns.session_id)

            {:noreply,
             socket
             |> assign_datos(datos)
             |> assign(errores: %{})
             |> feedback("Albergue registrado.", "success")}

          {:error, motivo} ->
            {:noreply, error_feedback(socket, motivo)}
        end

      _resultado ->
        {:noreply,
         feedback(socket, "La capacidad debe ser un número entero igual o mayor a cero.", "error")}
    end
  end

  def handle_event("registrar_entrada", %{"entrada" => attrs}, socket) do
    case API.ejecutar(
           socket.assigns.session_id,
           {:registrar_entrada_albergue, attrs["albergue_codigo"], attrs["persona_id"]}
         ) do
      {:ok, _estancia} ->
        datos = cargar_datos(socket.assigns.session_id)

        {:noreply,
         socket
         |> assign_datos(datos)
         |> feedback("Ingreso registrado; la disponibilidad se actualizó.", "success")}

      {:error, motivo} ->
        {:noreply, error_feedback(socket, motivo)}
    end
  end

  def handle_event("registrar_salida", %{"codigo" => codigo, "persona_id" => persona_id}, socket) do
    case API.ejecutar(
           socket.assigns.session_id,
           {:registrar_salida_albergue, codigo, persona_id}
         ) do
      {:ok, _estancia} ->
        datos = cargar_datos(socket.assigns.session_id)

        {:noreply,
         socket
         |> assign_datos(datos)
         |> feedback("Salida registrada; la plaza quedó disponible.", "success")}

      {:error, motivo} ->
        {:noreply, error_feedback(socket, motivo)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell
      title="Albergues"
      current_path="/albergues"
      current_user={@current_user}
      csrf_token={@csrf_token}
      flash={@flash}
    >
      <div class="mt-6">
        <p class="text-sm font-semibold uppercase tracking-widest text-orange-700">
          Módulo de Sergio Armero Salazar
        </p>

        <div class="mt-1 flex flex-wrap items-end justify-between gap-3">
          <div>
            <h1 class="text-3xl font-black">Albergues y ocupación</h1>

            <p class="mt-2 text-slate-600">
              Controla capacidad, plazas disponibles y estancias activas.
            </p>
          </div>

          <span class="rounded-xl border border-slate-200 bg-white px-4 py-3 text-sm"><strong class="text-lg">{map_size(
            @albergues
          )}</strong><span class="ml-2 text-slate-500">albergues</span></span>
        </div>
      </div>
      <AppShell.notice message={@mensaje} kind={@tipo_mensaje} />
      <div class="mt-6 grid gap-5 lg:grid-cols-2">
        <AppShell.panel
          :if={LiveAuth.administrador?(@current_user)}
          title="Registrar albergue"
          description="Asigna un código único, zona y capacidad máxima."
        >
          <.form
            for={%{}}
            as={:albergue}
            phx-change="validar_albergue"
            phx-submit="registrar_albergue"
            class="grid gap-3 sm:grid-cols-2"
          >
            <AppShell.field
              label="Código"
              name="albergue[codigo]"
              placeholder="A-02"
              pattern="A-[0-9]{2}"
              title="Usa el formato A-01."
              hint={Codigos.formato(:albergue)}
              error={@errores[:albergue]}
              required
            />
            <AppShell.field
              label="Nombre"
              name="albergue[nombre]"
              placeholder="Albergue municipal"
              required
            />
            <AppShell.select_field
              label="Zona"
              name="albergue[zona_codigo]"
              options={opciones_zona(@zonas)}
              value={zona_predeterminada(@zonas)}
              required
            />
            <AppShell.field
              label="Capacidad máxima"
              name="albergue[capacidad_maxima]"
              type="number"
              min="0"
              value="0"
              required
            />
            <button class="rounded-lg bg-orange-600 px-4 py-2.5 font-semibold text-white hover:bg-orange-500 sm:col-span-2">Registrar albergue</button>
          </.form>
        </AppShell.panel>

        <AppShell.panel
          :if={puede_gestionar_alguno?(@current_user, @albergues)}
          title="Registrar ingreso"
          description="La persona debe existir y no tener otra estancia activa."
        >
          <.form for={%{}} as={:entrada} phx-submit="registrar_entrada" class="space-y-3">
            <AppShell.select_field
              label="Albergue"
              name="entrada[albergue_codigo]"
              options={opciones_albergue(@albergues, @current_user)}
              value={albergue_predeterminado(@albergues)}
              required
            />
            <AppShell.select_field
              label="Persona afectada"
              name="entrada[persona_id]"
              options={Enum.map(@personas, fn {id, persona} -> {"#{persona.nombre} · #{id}", id} end)}
              value={persona_predeterminada(@personas)}
            />
            <button class="w-full rounded-lg bg-slate-900 px-4 py-2.5 font-semibold text-white hover:bg-slate-700">Registrar ingreso</button>
          </.form>
        </AppShell.panel>
      </div>

      <div class="mt-7 grid gap-5">
        <AppShell.panel
          :for={albergue <- albergues_visibles(@albergues, @current_user)}
          title={"#{albergue.codigo} · #{albergue.nombre}"}
          description={"Zona #{albergue.zona_codigo} · Capacidad #{albergue.capacidad_maxima} personas"}
        >
          <% resumen = @resumenes[albergue.codigo] %>
          <div class="grid gap-3 sm:grid-cols-3">
            <.metric label="Capacidad" value={resumen.capacidad} />
            <.metric label="Ocupadas" value={resumen.ocupadas} />
            <.metric label="Disponibles" value={resumen.disponibles} accent={resumen.disponibles > 0} />
          </div>

          <div class="mt-5 flex items-center justify-between gap-3">
            <h3 class="font-bold">Estancias activas</h3>

            <span class="text-xs text-slate-500">{length(
              estancias_activas(@estancias, albergue.codigo)
            )} personas</span>
          </div>

          <div
            :if={estancias_activas(@estancias, albergue.codigo) == []}
            class="mt-3 rounded-lg bg-slate-50 p-4 text-sm text-slate-500"
          >
            No hay personas alojadas actualmente.
          </div>

          <div
            :for={estancia <- estancias_activas(@estancias, albergue.codigo)}
            class="mt-3 flex flex-wrap items-center justify-between gap-3 rounded-xl border border-slate-200 px-4 py-3"
          >
            <div>
              <p class="font-semibold">{nombre_persona(@personas, estancia.persona_id)}</p>

              <p class="mt-0.5 text-xs text-slate-500">
                {estancia.persona_id} · Ingreso {estancia.fecha_ingreso}
              </p>
            </div>

            <button
              :if={LiveAuth.puede_gestionar_albergue?(@current_user, albergue)}
              type="button"
              phx-click="registrar_salida"
              phx-value-codigo={albergue.codigo}
              phx-value-persona_id={estancia.persona_id}
              class="rounded-lg border border-slate-300 px-3 py-2 text-sm font-semibold text-slate-700 hover:bg-slate-50"
            >Registrar salida</button>
          </div>
        </AppShell.panel>
      </div>
    </AppShell.shell>
    """
  end

  defp metric(assigns) do
    assigns = assign_new(assigns, :accent, fn -> false end)

    ~H"""
    <div class={if @accent, do: "rounded-xl bg-emerald-50 p-4", else: "rounded-xl bg-slate-50 p-4"}>
      <p class="text-xs font-semibold uppercase tracking-wide text-slate-500">{@label}</p>

      <p class="mt-1 text-2xl font-black">{@value}</p>
    </div>
    """
  end

  defp error_feedback(socket, :capacidad_insuficiente),
    do: feedback(socket, "El albergue alcanzó su capacidad máxima.", "error")

  defp error_feedback(socket, :persona_ya_albergada),
    do: feedback(socket, "La persona ya tiene una estancia activa.", "error")

  defp error_feedback(socket, :persona_no_encontrada),
    do: feedback(socket, "No se encontró esa persona en el registro.", "error")

  defp error_feedback(socket, :zona_no_encontrada),
    do: feedback(socket, "No se encontró la zona indicada.", "error")

  defp error_feedback(socket, :codigo_invalido),
    do: feedback(socket, "Revisa el formato del código: por ejemplo, A-01.", "error")

  defp error_feedback(socket, :id_duplicado),
    do: feedback(socket, "Ese código ya está registrado.", "error")

  defp error_feedback(socket, motivo),
    do: feedback(socket, "No fue posible completar la operación (#{humanizar(motivo)}).", "error")

  defp feedback(socket, mensaje, tipo), do: assign(socket, mensaje: mensaje, tipo_mensaje: tipo)

  defp humanizar(value) when is_atom(value),
    do: value |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()

  defp humanizar(value), do: to_string(value)

  defp opciones_zona(zonas) do
    zonas
    |> Map.values()
    |> Enum.map(&{"#{&1.nombre} · #{&1.codigo}", &1.codigo})
    |> Enum.sort_by(&elem(&1, 1))
  end

  defp opciones_albergue(albergues, usuario) do
    albergues
    |> Map.values()
    |> Enum.sort_by(& &1.codigo)
    |> Enum.filter(&LiveAuth.puede_gestionar_albergue?(usuario, &1))
    |> Enum.map(&{"#{&1.nombre} · #{&1.codigo}", &1.codigo})
  end

  defp albergues_visibles(albergues, usuario) do
    albergues
    |> Map.values()
    |> Enum.sort_by(& &1.codigo)
    |> Enum.filter(&(usuario.rol == :administrador or &1.zona_codigo == usuario.zona_principal))
  end

  defp puede_gestionar_alguno?(usuario, albergues),
    do: Enum.any?(Map.values(albergues), &LiveAuth.puede_gestionar_albergue?(usuario, &1))

  defp error_codigo(_tipo, nil), do: nil
  defp error_codigo(_tipo, ""), do: nil

  defp error_codigo(tipo, codigo) do
    if Codigos.valido?(tipo, codigo),
      do: nil,
      else: "Formato inválido. Ejemplo: #{Codigos.formato(tipo)}."
  end

  defp cargar_datos(session_id) do
    zonas = datos_o_vacio(API.consultar(session_id, :zonas)) |> Map.new(&{&1.codigo, &1})
    resumenes_lista = datos_o_vacio(API.consultar(session_id, :albergues))

    resumenes =
      Map.new(resumenes_lista, fn resumen -> {resumen.albergue.codigo, resumen} end)

    albergues =
      Map.new(resumenes_lista, fn resumen -> {resumen.albergue.codigo, resumen.albergue} end)

    personas =
      API.consultar(session_id, {:personas, %{}})
      |> datos_o_vacio()
      |> Map.new(&{&1.id, %{id: &1.id, nombre: &1.nombre}})

    estancias =
      albergues
      |> Map.keys()
      |> Enum.flat_map(fn codigo ->
        API.consultar(session_id, {:estancias_albergue, codigo}) |> datos_o_vacio()
      end)
      |> Map.new(&{&1.id, &1})

    %{
      zonas: zonas,
      resumenes: resumenes,
      albergues: albergues,
      personas: personas,
      estancias: estancias
    }
  end

  defp datos_o_vacio({:ok, datos}), do: datos
  defp datos_o_vacio(_error), do: []

  defp assign_datos(socket, datos),
    do: assign(socket, datos)

  defp estancias_activas(estancias, codigo),
    do: estancias |> Map.values() |> Enum.filter(&(&1.albergue_codigo == codigo))

  defp nombre_persona(personas, id), do: get_in(personas, [id, :nombre]) || id

  defp albergue_predeterminado(albergues),
    do: albergues |> Map.keys() |> Enum.sort() |> List.first() || ""

  defp zona_predeterminada(zonas), do: zonas |> Map.keys() |> Enum.sort() |> List.first() || ""

  defp persona_predeterminada(personas),
    do: personas |> Map.keys() |> Enum.sort() |> List.first() || ""
end
