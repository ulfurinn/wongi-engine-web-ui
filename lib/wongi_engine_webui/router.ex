defmodule WongiEngineWebui.Router do
  @moduledoc """
  Mounts the Wongi Engine UI in a Phoenix router.

      defmodule MyAppWeb.Router do
        use MyAppWeb, :router
        import WongiEngineWebui.Router

        scope "/" do
          pipe_through :browser

          # an editor for building rules
          wongi_engine_webui "/rules"

          # a read-only view of an existing engine
          wongi_engine_webui "/engine", engine: {MyApp.Rules, :engine, []}
        end
      end

  The UI is a LiveView served through the host's LiveView socket, so the
  host endpoint must declare one (the Phoenix default, `socket "/live", ...`).
  It ships its own JavaScript bundle, including the LiveView client; the host
  should run a compatible `phoenix_live_view` version.

  ## Options

    * `:engine` - `{module, function, args}` returning a `Wongi.Engine` or
      `{engine, rules}`, where `rules` are the `Wongi.Engine.DSL.Rule` structs
      that were compiled into it. Called on every mount. When given, the UI is
      read-only. Passing the rules lets it show their names and their
      original clause order, which can't be recovered from the network alone.

    * `:initial_rules` - `{module, function, args}` returning a list of
      `Wongi.Engine.DSL.Rule` structs to start the editor with.

    * `:initial_facts` - `{module, function, args}` returning a list of
      `{subject, predicate, object}` facts to start the editor's playground
      with.

    * `:evaluate` - whether the editor evaluates the Elixir code typed into
      it: `true`, `false` (the default), or `{module, function, args}`
      returning a boolean, called on mount. **Anyone who can open the page
      can run arbitrary code on the server when this is on**; only enable it
      for trusted users. When off, only literal values and a small set of
      known pure functions (`&min/1`, `&Enum.count/1`, `&is_integer/1`, ...)
      take effect; other functions are replaced by stand-ins (filters pass,
      actions do nothing), which the graph marks.

    * `:live_socket_path` - the host's LiveView socket path. Defaults to
      `"/live"`.

    * `:live_session_name` - the name of the `live_session` the UI is
      mounted in. Must be unique within the router when mounting more than
      once. Defaults to `:wongi_engine_webui`.

    * `:on_mount` - `on_mount` hooks for the `live_session`, for example to
      authenticate users.
  """

  @doc "Mounts the UI at `path`. See the module docs for options."
  defmacro wongi_engine_webui(path, opts \\ []) do
    quote bind_quoted: [path: path, opts: opts] do
      prefix = Phoenix.Router.scoped_path(__MODULE__, path)

      scope path, alias: false, as: false do
        import Phoenix.Router, only: [get: 3]
        import Phoenix.LiveView.Router, only: [live: 3, live_session: 3]

        {session_name, session_opts} = WongiEngineWebui.Router.__options__(prefix, opts)

        get "/_assets/:asset", WongiEngineWebuiWeb.Assets, :show

        live_session session_name, session_opts do
          live "/", WongiEngineWebuiWeb.EngineLive, :index
        end
      end
    end
  end

  @doc false
  def __options__(prefix, opts) do
    engine = opts |> Keyword.get(:engine) |> validate_mfa!(:engine)
    initial_rules = opts |> Keyword.get(:initial_rules) |> validate_mfa!(:initial_rules)
    initial_facts = opts |> Keyword.get(:initial_facts) |> validate_mfa!(:initial_facts)

    evaluate =
      case Keyword.get(opts, :evaluate, false) do
        flag when is_boolean(flag) -> flag
        mfa -> validate_mfa!(mfa, :evaluate)
      end

    socket_path = Keyword.get(opts, :live_socket_path, "/live")

    session_opts =
      [
        session:
          {__MODULE__, :__session__,
           [prefix, engine, initial_rules, initial_facts, evaluate, socket_path]},
        root_layout: {WongiEngineWebuiWeb.Layouts, :root}
      ] ++ Keyword.take(opts, [:on_mount])

    {Keyword.get(opts, :live_session_name, :wongi_engine_webui), session_opts}
  end

  defp validate_mfa!(nil, _option), do: nil

  defp validate_mfa!({m, f, a} = mfa, _option) when is_atom(m) and is_atom(f) and is_list(a),
    do: mfa

  defp validate_mfa!(other, option) do
    raise ArgumentError,
          "expected #{inspect(option)} to be a {module, function, args} tuple, got: #{inspect(other)}"
  end

  @doc false
  def __session__(_conn, prefix, engine, initial_rules, initial_facts, evaluate, socket_path) do
    %{
      "prefix" => String.trim_trailing(prefix, "/"),
      "engine" => engine,
      "initial_rules" => initial_rules,
      "initial_facts" => initial_facts,
      "evaluate" => evaluate,
      "live_socket_path" => socket_path
    }
  end
end
