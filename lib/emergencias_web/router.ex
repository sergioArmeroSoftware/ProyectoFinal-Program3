defmodule EmergenciasWeb.Router do
  use EmergenciasWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {EmergenciasWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", EmergenciasWeb do
    pipe_through(:browser)

    live("/", PanelLive, :inicio)
    live("/usuarios", PanelLive, :usuarios)
    live("/zonas", PanelLive, :zonas)
    live("/albergues", PanelLive, :albergues)
    live("/personas", PersonasLive, :index)
    live("/mensajes", MensajesLive, :index)
    live("/necesidades", NecesidadesLive, :index)
    live("/recursos", RecursosLive, :index)
  end

  # Other scopes may use custom stacks.
  # scope "/api", EmergenciasWeb do
  #   pipe_through :api
  # end
end
