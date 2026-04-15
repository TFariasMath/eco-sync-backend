defmodule EcoSyncBackend.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      EcoSyncBackendWeb.Telemetry,
      {Phoenix.PubSub, name: EcoSyncBackend.PubSub},
      EcoSyncBackendWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: EcoSyncBackend.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    EcoSyncBackendWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
