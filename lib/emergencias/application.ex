defmodule Emergencias.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    role = Application.get_env(:emergencias, :node_role, :all)
    children = children_for(role)
    Supervisor.start_link(children, strategy: :one_for_one, name: Emergencias.Supervisor)
  end

  defp children_for(:core), do: [Emergencias.EstadoServidor]

  defp children_for(:web), do: web_children()

  defp children_for(:all), do: [Emergencias.EstadoServidor | web_children()]

  defp web_children do
    [
      EmergenciasWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:emergencias, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Emergencias.PubSub},
      EmergenciasWeb.Endpoint
    ]
  end

  @impl true
  def config_change(changed, _new, removed) do
    if Application.get_env(:emergencias, :node_role, :all) in [:web, :all],
      do: EmergenciasWeb.Endpoint.config_change(changed, removed)

    :ok
  end
end
