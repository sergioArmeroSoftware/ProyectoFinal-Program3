defmodule EmergenciasWeb.LiveAuth do
  @moduledoc "Exige una cuenta activa y aplica permisos al despachar eventos LiveView."
  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  alias Emergencias.Usuarios
  alias Emergencias.API

  @admin_only_events ~w(
    registrar_usuario asignar_rol desactivar_usuario
    crear_zona agregar_sector agregar_punto alternar_punto registrar_albergue
  )

  def on_mount(:default, _params, %{"session_id" => session_id} = session, socket)
      when is_binary(session_id) do
    case API.consultar(session_id, :sesion_actual) do
      {:ok, usuario} ->
        socket =
          socket
          |> assign(:current_user, usuario)
          |> assign(:session_id, session_id)
          |> assign(:csrf_token, session["csrf_token"])
          |> attach_hook(:demo_permissions, :handle_event, &authorize_event/3)

        {:cont, socket}

      _resultado ->
        {:halt, redirect(socket, to: "/acceso")}
    end
  end

  def on_mount(:default, _params, _session, socket), do: {:halt, redirect(socket, to: "/acceso")}

  @doc "Comprueba si el usuario activo puede administrar cuentas."
  def administrador?(%{rol: :administrador, activo: true}), do: true
  def administrador?(_usuario), do: false

  @doc "Comprueba permiso sobre una estancia de albergue en la zona del usuario."
  def puede_gestionar_albergue?(usuario, albergue) do
    Usuarios.permitido?(usuario.rol, :gestionar_albergue) and
      (usuario.rol == :administrador or usuario.zona_principal == albergue.zona_codigo)
  end

  defp authorize_event(event, _params, socket) when event in @admin_only_events do
    if administrador?(socket.assigns.current_user) do
      {:cont, socket}
    else
      {:halt, put_flash(socket, :error, "Tu rol no permite ejecutar esa acción.")}
    end
  end

  defp authorize_event(
         "registrar_entrada",
         %{"entrada" => %{"albergue_codigo" => codigo}},
         socket
       ),
       do: authorize_shelter(codigo, socket)

  defp authorize_event("registrar_salida", %{"codigo" => codigo}, socket),
    do: authorize_shelter(codigo, socket)

  defp authorize_event(_event, _params, socket), do: {:cont, socket}

  defp authorize_shelter(codigo, socket) do
    case Map.get(socket.assigns[:albergues] || %{}, codigo) do
      nil ->
        {:halt, put_flash(socket, :error, "No se encontró el albergue indicado.")}

      albergue ->
        if puede_gestionar_albergue?(socket.assigns.current_user, albergue) do
          {:cont, socket}
        else
          {:halt, put_flash(socket, :error, "Tu rol o zona no permite gestionar este albergue.")}
        end
    end
  end
end
