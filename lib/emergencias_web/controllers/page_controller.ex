defmodule EmergenciasWeb.PageController do
  use EmergenciasWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
