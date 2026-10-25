# WongiEngineWebui

A visual editor and viewer for [Wongi.Engine](https://wongi-engine.hexdocs.pm/Wongi.Engine.html)
rules. It draws the beta network that a set of rules compiles to, with the
Elixir source of the rules alongside.

* **Editor**: build rules from clauses (`has`, `neg`, `ncc`, `any`, filters,
  `assign`, `aggregate`) and actions. The network and the code update as you
  type. Values and functions are written as Elixir expressions, which are
  parsed to check them but never evaluated.
* **Read-only**: given a compiled engine, shows its network, token counts per
  node, and the rules recovered from it.

Click a node to see what it matches and which rules share it; click a rule's
code to highlight its path through the network.

## Embedding in a Phoenix app

Add the dependency, then mount the UI in your router:

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router
  import WongiEngineWebui.Router

  scope "/" do
    pipe_through :browser

    wongi_engine_webui "/rules"
    wongi_engine_webui "/engine", engine: {MyApp.Rules, :engine, []},
      live_session_name: :wongi_engine
  end
end
```

`MyApp.Rules.engine/0` returns either a `Wongi.Engine` or `{engine, rules}`.
Passing the `Wongi.Engine.DSL.Rule` structs as well lets the UI show rule names
and the original clause order, which can't be recovered from the network.

The UI is a LiveView that runs over the host's LiveView socket and ships its own
JS and CSS bundle, served from the mount path, so the host needs no asset
changes. See `WongiEngineWebui.Router` for all options, including `on_mount`
for authentication.

## Standalone server

The standalone server only starts when `WONGI_ENGINE_WEBUI_SERVER` is set, so it
never clashes with a host application:

```sh
mix setup
WONGI_ENGINE_WEBUI_SERVER=1 mix phx.server
```

Then open [localhost:4000](http://localhost:4000) for the editor (preloaded with
`WongiEngineWebui.Example`) or [localhost:4000/example](http://localhost:4000/example)
for a read-only view of the example engine.

## Development

Assets are built with [Volt](https://volt.hexdocs.pm); in development
`Volt.DevServer` serves and hot-reloads them. The layout engine,
[elkjs](https://github.com/kieler/elkjs), is installed with npm (`mix setup`
does this).

The production bundle in `priv/assets` is embedded into
`WongiEngineWebuiWeb.Assets` at compile time and is committed, since host
applications don't build it. Rebuild it with `mix assets.build` after changing
anything under `assets/`.
