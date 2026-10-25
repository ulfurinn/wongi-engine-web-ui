defmodule WongiEngineWebui.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    opts = [strategy: :one_for_one, name: WongiEngineWebui.Supervisor]
    Supervisor.start_link(children(), opts)
  end

  # As a dependency the UI runs inside the host's endpoint, so the standalone
  # server only starts on request, to avoid clashing with the host's port.
  defp children do
    if standalone?() do
      [
        WongiEngineWebuiWeb.Telemetry,
        {DNSCluster,
         query: Application.get_env(:wongi_engine_webui, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: WongiEngineWebui.PubSub},
        WongiEngineWebuiWeb.Endpoint
      ]
    else
      []
    end
  end

  @doc false
  def standalone? do
    System.get_env("WONGI_ENGINE_WEBUI_SERVER") in ~w(1 true) or
      Application.get_env(:wongi_engine_webui, :standalone, false)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    if standalone?(), do: WongiEngineWebuiWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
