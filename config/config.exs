# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :wongi_engine_webui,
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :wongi_engine_webui, WongiEngineWebuiWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: WongiEngineWebuiWeb.ErrorHTML, json: WongiEngineWebuiWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: WongiEngineWebui.PubSub,
  live_view: [signing_salt: "GZv8hH+m"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure Volt (frontend build tool)
config :volt,
  entry: "assets/js/app.js",
  root: "assets",
  outdir: "priv/static/assets",
  target: :es2022,
  sourcemap: :hidden,
  # LiveView writes colocated hooks/CSS to _build/$MIX_ENV/phoenix-colocated/
  resolve_dirs: [Path.expand("../deps", __DIR__), Mix.Project.build_path()]

# Configure `mix volt.lint` (oxlint)
config :volt, :lint,
  plugins: ["typescript", "import", "unicorn"],
  rules: %{
    "no-debugger" => :deny,
    "no-unused-vars" => :warn,
    "no-console" => :warn,
    "no-empty-function" => :deny,
    "eqeqeq" => :deny,
    "no-var" => :deny,
    "prefer-const" => :deny,
    "typescript/no-explicit-any" => :warn,
    "typescript/no-non-null-assertion" => :warn,
    "typescript/consistent-type-imports" => :deny,
    "typescript/no-floating-promises" => :deny,
    "typescript/no-misused-promises" => :deny,
    "import/no-cycle" => :deny,
    "import/no-self-import" => :deny,
    "import/no-duplicates" => :deny,
    "import/no-mutable-exports" => :deny,
    "unicorn/no-instanceof-array" => :deny,
    "unicorn/no-typeof-undefined" => :deny,
    "unicorn/no-nested-ternary" => :deny,
    "unicorn/no-useless-fallback-in-spread" => :deny,
    "unicorn/no-unnecessary-await" => :deny,
    "unicorn/prefer-string-starts-ends-with" => :deny
  }

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
