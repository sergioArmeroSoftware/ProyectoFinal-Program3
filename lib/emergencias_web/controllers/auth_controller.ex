defmodule EmergenciasWeb.AuthController do
  @moduledoc "Establece y elimina la cookie de sesión de la demostración."
  use EmergenciasWeb, :controller

  alias EmergenciasWeb.DemoEstado

  def create(conn, %{"usuario" => attrs}) do
    modo = Map.get(attrs, "modo", "ingresar")

    if modo == "registro" and attrs["password"] != attrs["password_confirmation"] do
      conn
      |> redirect(to: "/acceso?modo=registro&error=contrasenas_distintas")
    else
      attrs = Map.drop(attrs, ["modo", "password_confirmation"])

      resultado =
        if modo == "registro", do: DemoEstado.registrar(attrs), else: DemoEstado.ingresar(attrs)

      establecer_sesion(conn, resultado, modo)
    end
  end

  def create(conn, _params), do: conn |> redirect(to: "/acceso?error=datos_incompletos")

  def delete(conn, _params) do
    DemoEstado.salir(get_session(conn, :demo_session_id))

    conn
    |> configure_session(drop: true)
    |> redirect(to: "/acceso?mensaje=sesion_cerrada")
  end

  defp establecer_sesion(conn, {:ok, %{session_id: session_id}}, _modo) do
    conn
    |> configure_session(renew: true)
    |> put_session(:demo_session_id, session_id)
    |> redirect(to: "/")
  end

  defp establecer_sesion(conn, {:error, motivo}, modo) do
    modo = if modo == "registro", do: "registro", else: "ingresar"
    error = error_key(motivo)
    redirect(conn, to: "/acceso?modo=#{modo}&error=#{error}")
  end

  defp error_key(:credenciales_invalidas), do: "credenciales_invalidas"
  defp error_key(:contrasena_invalida), do: "contrasena_invalida"
  defp error_key(:id_duplicado), do: "usuario_existente"
  defp error_key(:zona_requerida), do: "zona_requerida"
  defp error_key(:codigo_invalido), do: "codigo_invalido"
  defp error_key(:zona_no_encontrada), do: "zona_no_encontrada"
  defp error_key(_motivo), do: "datos_incompletos"
end
