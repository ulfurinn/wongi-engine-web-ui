defmodule WongiEngineWebuiWeb.Router do
  @moduledoc """
  The standalone server's router. It mounts the UI the same way a host
  application would (see `WongiEngineWebui.Router`), using the example rules.
  """
  use WongiEngineWebuiWeb, :router

  import WongiEngineWebui.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/" do
    pipe_through :browser

    wongi_engine_webui "/example",
      engine: {WongiEngineWebui.Example, :engine, []},
      live_session_name: :wongi_engine_webui_example

    wongi_engine_webui "/",
      initial_rules: {WongiEngineWebui.Example, :rules, []},
      initial_facts: {WongiEngineWebui.Example, :facts, []},
      evaluate: {WongiEngineWebui.Example, :evaluate?, []}
  end
end
