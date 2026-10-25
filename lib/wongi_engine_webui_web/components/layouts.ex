defmodule WongiEngineWebuiWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use WongiEngineWebuiWeb, :html

  # Embed all files in layouts/* within this module.
  # The root layout is rendered with the LiveView's assigns, which provide
  # `@asset_js`, `@asset_css` and `@live_socket_path` (see `asset_assigns/2`).
  embed_templates "layouts/*"

  @doc """
  Asset URLs for the root layout.

  In the standalone server with code reloading, assets come from
  `Volt.DevServer`, which injects the CSS itself. Everywhere else, including
  host applications, they come from `WongiEngineWebuiWeb.Assets` under the
  mount `prefix`.
  """
  def asset_assigns(endpoint, prefix) do
    if endpoint == WongiEngineWebuiWeb.Endpoint and endpoint.config(:code_reloader) do
      %{asset_js: "/assets/js/app.js", asset_css: nil}
    else
      %{
        asset_js: "#{prefix}/_assets/#{WongiEngineWebuiWeb.Assets.name(:js)}",
        asset_css: "#{prefix}/_assets/#{WongiEngineWebuiWeb.Assets.name(:css)}"
      }
    end
  end

  @doc """
  Renders your app layout.

  A full-height shell with a header bar; the content fills the rest.

  ## Examples

      <Layouts.app flash={@flash} subtitle="Editor">
        <:actions><.button>Reset</.button></:actions>
        ...
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :subtitle, :string, default: nil
  slot :actions
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="app">
      <header class="app-header">
        <div class="app-brand">
          <span class="app-logo" aria-hidden="true">
            <.icon name="hero-share" />
          </span>
          <span class="app-title">Wongi Engine</span>
          <span :if={@subtitle} class="app-subtitle">{@subtitle}</span>
        </div>
        <div class="app-actions">{render_slot(@actions)}</div>
      </header>

      <main class="app-main">
        {render_slot(@inner_block)}
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} class="flash-group" aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title="We can't find the internet"
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect <.icon name="hero-arrow-path" class="spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong!"
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect <.icon name="hero-arrow-path" class="spin" />
      </.flash>
    </div>
    """
  end
end
