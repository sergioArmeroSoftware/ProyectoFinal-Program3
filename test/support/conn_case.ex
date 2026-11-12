defmodule EmergenciasWeb.ConnCase do
  @moduledoc "Infraestructura web aislada para pruebas con mix test --no-start."
  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint EmergenciasWeb.Endpoint
      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
    end
  end

  setup do
    {:ok, _apps} = Application.ensure_all_started(:phoenix_live_view)
    {:ok, _apps} = Application.ensure_all_started(:lazy_html)
    start_supervised!({Phoenix.PubSub, name: Emergencias.PubSub})
    start_supervised!(EmergenciasWeb.Endpoint)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
