defmodule EmergenciasWeb.AlberguesLive do
  @moduledoc "Interfaz de demostración para capacidad y estancias en albergues."
  use EmergenciasWeb, :live_view

  alias Emergencias.{Albergue, EstanciaAlbergue}
  alias EmergenciasWeb.AppShell
  alias EmergenciasWeb.LiveAuth
  alias EmergenciasWeb.Demo

  @impl true
  def mount(_params, _session, socket) do
    fecha = Date.utc_today()

    albergue = %Albergue{
      codigo: "A-01",
      nombre: "Centro Educativo Los Álamos",
      zona_codigo: "Z-01",
      capacidad_maxima: 6
    }

    estancias = %{
      "EST-01" => %EstanciaAlbergue{
        id: "EST-01",
        albergue_codigo: "A-01",
        persona_id: "P-001",
        fecha_ingreso: fecha
      },
      "EST-02" => %EstanciaAlbergue{
        id: "EST-02",
        albergue_codigo: "A-01",
        persona_id: "P-002",
        fecha_ingreso: fecha
      }
    }

    personas = %{
      "P-001" => %{id: "P-001", nombre: "Persona de demostración 1"},
      "P-002" => %{id: "P-002", nombre: "Persona de demostración 2"},
      "P-003" => %{id: "P-003", nombre: "Persona de demostración 3"}
    }

    {:ok,
     assign(socket,
       albergues: %{albergue.codigo => albergue},
       zonas: %{
         "Z-01" => %{codigo: "Z-01"},
         "Z-02" => %{codigo: "Z-02"}
       },
       estancias: estancias,
       personas: personas,
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

        case Demo.registrar_albergue(socket.assigns.albergues, socket.assigns.zonas, attrs) do
          {:ok, albergues} ->
            {:noreply,
             socket
             |> assign(albergues: albergues, errores: %{})
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
    estancia_id = "EST-#{System.unique_integer([:positive, :monotonic])}"

    case Demo.registrar_ingreso(
           socket.assigns.albergues,
           socket.assigns.estancias,
           socket.assigns.personas,
           attrs["albergue_codigo"],
           attrs["persona_id"],
           estancia_id,
           Date.utc_today()
         ) do
      {:ok, estancias} ->
        {:noreply,
         socket
         |> assign(estancias: estancias)
         |> feedback("Ingreso registrado; la disponibilidad se actualizó.", "success")}

      {:error, motivo} ->
        {:noreply, error_feedback(socket, motivo)}
    end
  end

  def handle_event("registrar_salida", %{"codigo" => codigo, "persona_id" => persona_id}, socket) do
    case Demo.registrar_salida(
           socket.assigns.estancias,
           codigo,
           persona_id,
           Date.utc_today()
         ) do
      {:ok, estancias} ->
        {:noreply,
         socket
         |> assign(estancias: estancias)
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
      <AppShell.notice message="Prototipo: los cambios viven en esta conexión LiveView y no se guardan en el archivo todavía." />
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
              hint={Demo.formato_codigo(:albergue)}
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
              value="Z-01"
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
              value="A-01"
              required
            />
            <AppShell.select_field
              label="Persona afectada"
              name="entrada[persona_id]"
              options={Enum.map(@personas, fn {id, persona} -> {"#{persona.nombre} · #{id}", id} end)}
              value="P-003"
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
          <% {:ok, resumen} = Demo.disponibilidad(@albergues, @estancias, albergue.codigo) %>
          <div class="grid gap-3 sm:grid-cols-3">
            <.metric label="Capacidad" value={resumen.capacidad} />
            <.metric label="Ocupadas" value={resumen.ocupadas} />
            <.metric label="Disponibles" value={resumen.disponibles} accent={resumen.disponibles > 0} />
          </div>

          <div class="mt-5 flex items-center justify-between gap-3">
            <h3 class="font-bold">Estancias activas</h3>
            <span class="text-xs text-slate-500">{length(
              Demo.estancias_activas(@estancias, albergue.codigo)
            )} personas</span>
          </div>
          <div
            :if={Demo.estancias_activas(@estancias, albergue.codigo) == []}
            class="mt-3 rounded-lg bg-slate-50 p-4 text-sm text-slate-500"
          >
            No hay personas alojadas actualmente.
          </div>
          <div
            :for={estancia <- Demo.estancias_activas(@estancias, albergue.codigo)}
            class="mt-3 flex flex-wrap items-center justify-between gap-3 rounded-xl border border-slate-200 px-4 py-3"
          >
            <div>
              <p class="font-semibold">{@personas[estancia.persona_id].nombre}</p>
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
    |> Enum.map(fn {codigo, zona} ->
      {"#{Map.get(zona, :nombre, codigo)} · #{codigo}", codigo}
    end)
    |> Enum.sort_by(&elem(&1, 1))
  end

  defp opciones_albergue(albergues, usuario) do
    albergues
    |> Demo.listar_albergues()
    |> Enum.filter(&LiveAuth.puede_gestionar_albergue?(usuario, &1))
    |> Enum.map(&{"#{&1.nombre} · #{&1.codigo}", &1.codigo})
  end

  defp albergues_visibles(albergues, usuario) do
    albergues
    |> Demo.listar_albergues()
    |> Enum.filter(&(usuario.rol == :administrador or &1.zona_codigo == usuario.zona_principal))
  end

  defp puede_gestionar_alguno?(usuario, albergues),
    do:
      Enum.any?(
        Demo.listar_albergues(albergues),
        &LiveAuth.puede_gestionar_albergue?(usuario, &1)
      )

  defp error_codigo(_tipo, nil), do: nil
  defp error_codigo(_tipo, ""), do: nil

  defp error_codigo(tipo, codigo) do
    if Demo.valido_codigo?(tipo, codigo),
      do: nil,
      else: "Formato inválido. Ejemplo: #{Demo.formato_codigo(tipo)}."
  end
end
