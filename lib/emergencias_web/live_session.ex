defmodule EmergenciasWeb.LiveSession do
  @moduledoc "Transfiere el token firmado de Plug.Session al ciclo de vida LiveView."

  def session(conn) do
    %{
      "csrf_token" => Plug.CSRFProtection.get_csrf_token(),
      "demo_session_id" => Plug.Conn.get_session(conn, :demo_session_id)
    }
  end
end
