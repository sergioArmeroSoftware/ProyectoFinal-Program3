defmodule EmergenciasWeb.UsuariosLive do
  @moduledoc "Interfaz de demostración para registro, consulta y roles de usuarios."
  use EmergenciasWeb, :live_view

  alias Emergencias.{API, Usuarios}
  alias EmergenciasWeb.AppShell
  alias EmergenciasWeb.LiveAuth

  @impl true
  def mount(_params, session, socket) do
    usuarios = datos_o_vacio(API.consultar(session["session_id"], :usuarios))
    zonas = datos_o_vacio(API.consultar(session["session_id"], :zonas))

    {:ok,
     assign(socket,
       usuarios: usuarios,
       zonas: Enum.map(zonas, &{"#{&1.nombre} · #{&1.codigo}", &1.codigo}),
       mensaje: nil,
       tipo_mensaje: "info",
       roles: Enum.map(Usuarios.roles(), &{humanizar(&1), Atom.to_string(&1)})
     )}
  end

  @impl true
  def handle_event("registrar_usuario", %{"usuario" => attrs}, socket) do
    case API.ejecutar(socket.assigns.session_id, {:registrar_usuario, attrs}) do
      {:ok, _usuario} ->
        {:noreply,
         socket
         |> recargar_usuarios()
         |> feedback("Cuenta creada con rol ciudadano.", "success")}

      {:error, :id_duplicado} ->
        {:noreply, feedback(socket, "Ya existe una cuenta con ese usuario.", "error")}

      {:error, :contrasena_invalida} ->
        {:noreply,
         feedback(socket, "La contraseña debe tener al menos ocho caracteres.", "error")}

      {:error, :codigo_invalido} ->
        {:noreply, feedback(socket, "El código de zona debe tener el formato Z-01.", "error")}

      {:error, :zona_requerida} ->
        {:noreply, feedback(socket, "Selecciona una zona principal.", "error")}

      {:error, :zona_no_encontrada} ->
        {:noreply, feedback(socket, "Selecciona una zona existente.", "error")}

      {:error, motivo} ->
        {:noreply,
         feedback(socket, "Revisa los datos ingresados (#{humanizar(motivo)}).", "error")}
    end
  end

  def handle_event(
        "asignar_rol",
        %{"cambio" => %{"username" => username, "rol" => rol_texto}},
        socket
      ) do
    rol = Enum.find(Usuarios.roles(), &(Atom.to_string(&1) == rol_texto))

    case API.ejecutar(socket.assigns.session_id, {:asignar_rol, username, rol}) do
      {:ok, _usuario} ->
        {:noreply,
         socket
         |> recargar_usuarios()
         |> feedback("Rol actualizado para #{username}.", "success")}

      {:error, :rol_invalido} ->
        {:noreply, feedback(socket, "Selecciona un rol válido.", "error")}

      {:error, motivo} ->
        {:noreply, feedback(socket, "No se pudo cambiar el rol (#{humanizar(motivo)}).", "error")}
    end
  end

  def handle_event("desactivar_usuario", %{"username" => username}, socket) do
    case API.ejecutar(socket.assigns.session_id, {:desactivar_usuario, username}) do
      {:ok, _respuesta} ->
        {:noreply,
         socket
         |> recargar_usuarios()
         |> feedback("La cuenta #{username} quedó desactivada.", "success")}

      {:error, motivo} ->
        {:noreply,
         feedback(socket, "No se pudo desactivar la cuenta (#{humanizar(motivo)}).", "error")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell
      title="Usuarios"
      current_path="/usuarios"
      current_user={@current_user}
      csrf_token={@csrf_token}
      flash={@flash}
    >
      <AppShell.notice
        :if={!LiveAuth.administrador?(@current_user)}
        message="La consulta y administración de cuentas están reservadas al rol administrador."
      />
      <div class="mt-6 flex flex-wrap items-end justify-between gap-3">
        <div>
          <p class="text-sm font-semibold uppercase tracking-widest text-orange-700">
            Administración del sistema
          </p>

          <h1 class="mt-1 text-3xl font-black">Usuarios y permisos</h1>

          <p class="mt-2 text-slate-600">
            Alta ciudadana, administración de roles y estado de las cuentas.
          </p>
        </div>

        <div
          :if={LiveAuth.administrador?(@current_user)}
          class="rounded-xl border border-slate-200 bg-white px-4 py-3 text-sm"
        >
          <span class="text-slate-500">Cuentas en la vista</span>
          <strong class="ml-2 text-lg">{length(@usuarios)}</strong>
        </div>
      </div>

      <div class="mt-7 grid gap-6 xl:grid-cols-[0.85fr_1.15fr]">
        <AppShell.panel
          :if={LiveAuth.administrador?(@current_user)}
          title="Registrar ciudadano"
          description="El alta pública nunca asigna roles privilegiados."
        >
          <.form for={%{}} as={:usuario} phx-submit="registrar_usuario" class="space-y-4">
            <AppShell.field
              label="Nombre de usuario"
              name="usuario[username]"
              placeholder="ej. maria.mejia"
              required
            />
            <AppShell.field
              label="Nombre completo"
              name="usuario[nombre_completo]"
              placeholder="Nombre y apellidos"
              required
            />
            <AppShell.field
              label="Contraseña"
              name="usuario[password]"
              type="password"
              placeholder="Mínimo 8 caracteres"
              required
            />
            <AppShell.select_field
              label="Zona principal"
              name="usuario[zona_principal]"
              options={@zonas}
              value="Z-01"
              required
            /> <AppShell.notice message={@mensaje} kind={@tipo_mensaje} />
            <button
              type="submit"
              class="w-full rounded-lg bg-orange-600 px-4 py-3 font-semibold text-white hover:bg-orange-500"
            >Crear ciudadano</button>
          </.form>
        </AppShell.panel>

        <AppShell.panel
          :if={LiveAuth.administrador?(@current_user)}
          title="Cuentas registradas"
          description="Cuentas y roles guardados por el coordinador."
        >
          <div class="overflow-x-auto">
            <table class="w-full min-w-[540px] text-left text-sm">
              <thead class="border-b border-slate-200 text-xs uppercase tracking-wide text-slate-500">
                <tr>
                  <th class="py-3 pr-4">Persona</th><th class="py-3 pr-4">Zona</th><th class="py-3 pr-4">
                    Rol
                  </th><th class="py-3">Estado</th>
                </tr>
              </thead>

              <tbody class="divide-y divide-slate-100">
                <tr :for={usuario <- @usuarios}>
                  <td class="py-4 pr-4">
                    <p class="font-semibold text-slate-900">{usuario.nombre_completo}</p>

                    <p class="text-xs text-slate-500">@{usuario.username}</p>
                  </td>

                  <td class="py-4 pr-4 text-slate-600">{usuario.zona_principal || "—"}</td>

                  <td class="py-4 pr-4">
                    <.form
                      :if={LiveAuth.administrador?(@current_user) and usuario.activo}
                      for={%{}}
                      as={:cambio}
                      phx-submit="asignar_rol"
                      class="flex items-center gap-2"
                    >
                      <input type="hidden" name="cambio[username]" value={usuario.username} />
                      <select
                        name="cambio[rol]"
                        class="rounded-md border border-slate-300 bg-white px-2 py-1.5 text-xs"
                      >
                        <option
                          :for={{label, value} <- @roles}
                          value={value}
                          selected={Atom.to_string(usuario.rol) == value}
                        >
                          {label}
                        </option>
                      </select>

                      <button class="rounded-md bg-slate-900 px-2.5 py-1.5 text-xs font-semibold text-white hover:bg-slate-700">Aplicar</button>
                    </.form>

                    <span
                      :if={!LiveAuth.administrador?(@current_user) or not usuario.activo}
                      class="inline-flex rounded-full bg-slate-100 px-2.5 py-1 text-xs font-semibold text-slate-700"
                    >{humanizar(usuario.rol)}</span>
                  </td>

                  <td class="py-4">
                    <div class="flex items-center gap-2">
                      <span class={
                        if usuario.activo,
                          do:
                            "rounded-full bg-emerald-100 px-2.5 py-1 text-xs font-semibold text-emerald-800",
                          else:
                            "rounded-full bg-slate-100 px-2.5 py-1 text-xs font-semibold text-slate-500"
                      }>
                        {if usuario.activo, do: "Activa", else: "Inactiva"}
                      </span>

                      <button
                        :if={LiveAuth.administrador?(@current_user) and usuario.activo}
                        type="button"
                        phx-click="desactivar_usuario"
                        phx-value-username={usuario.username}
                        class="text-xs font-medium text-rose-700 hover:underline"
                      >Desactivar</button>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <p class="mt-4 text-xs leading-5 text-slate-500">
            Cada cambio de rol se valida en el coordinador usando la sesión activa del administrador.
          </p>
        </AppShell.panel>
      </div>

      <AppShell.notice
        :if={!LiveAuth.administrador?(@current_user)}
        message="El listado y la administración de cuentas están reservados al rol administrador."
      />
    </AppShell.shell>
    """
  end

  defp feedback(socket, mensaje, tipo), do: assign(socket, mensaje: mensaje, tipo_mensaje: tipo)

  defp recargar_usuarios(socket) do
    assign(socket, usuarios: datos_o_vacio(API.consultar(socket.assigns.session_id, :usuarios)))
  end

  defp datos_o_vacio({:ok, datos}), do: datos
  defp datos_o_vacio(_error), do: []

  defp humanizar(value) when is_atom(value),
    do: value |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()

  defp humanizar(value), do: to_string(value)
end
