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

  @logo_path Path.expand("../../../assets/images/wongi.svg", __DIR__)
  @external_resource @logo_path
  @logo_d @logo_path |> File.read!() |> then(&Regex.run(~r/\sd="([^"]+)"/, &1)) |> List.last()

  @doc "The project logo (cherries), inline, in the current text colour."
  attr :class, :any, default: nil

  def logo(assigns) do
    assigns = assign(assigns, :d, @logo_d)

    ~H"""
    <svg
      class={@class}
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 170.1 170.1"
      fill="currentColor"
      aria-hidden="true"
    >
      <path d={@d} />
    </svg>
    """
  end

  # A data URI, so the favicon works wherever the UI is mounted.
  @favicon "data:image/svg+xml," <>
             URI.encode(
               ~s(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 170.1 170.1">) <>
                 ~s(<path fill="#63a" d="#{@logo_d}"/></svg>),
               &URI.char_unreserved?/1
             )

  @doc false
  def favicon, do: @favicon

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
          <span class="app-logo"><.logo /></span>
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
