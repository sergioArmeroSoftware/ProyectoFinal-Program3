defmodule EmergenciasWeb.Router do
  use EmergenciasWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {EmergenciasWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", EmergenciasWeb do
    pipe_through :browser

    live_session :public, session: {EmergenciasWeb.LiveSession, :session, []} do
      live "/acceso", AccesoLive, :acceso
    end

    post "/sesion", AuthController, :create
    delete "/sesion", AuthController, :delete

    live_session :authenticated,
      session: {EmergenciasWeb.LiveSession, :session, []},
      on_mount: [EmergenciasWeb.LiveAuth] do
      live "/", PanelLive, :inicio
      live "/usuarios", UsuariosLive, :usuarios
      live "/zonas", ZonasLive, :zonas
      live "/albergues", AlberguesLive, :albergues
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", EmergenciasWeb do
  #   pipe_through :api
  # end
end
