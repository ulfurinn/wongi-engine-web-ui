defmodule WongiEngineWebui.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      WongiEngineWebuiWeb.Telemetry,
      {DNSCluster,
       query: Application.get_env(:wongi_engine_webui, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: WongiEngineWebui.PubSub},
      # Start a worker by calling: WongiEngineWebui.Worker.start_link(arg)
      # {WongiEngineWebui.Worker, arg},
      # Start to serve requests, typically the last entry
      WongiEngineWebuiWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: WongiEngineWebui.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    WongiEngineWebuiWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
