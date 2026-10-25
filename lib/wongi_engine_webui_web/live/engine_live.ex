defmodule WongiEngineWebuiWeb.EngineLive do
  @moduledoc """
  The rule editor and network viewer.

  Without an engine in the session it is an editor and playground: rules and
  facts are edited as specs, compiled into a fresh engine on every change, and
  the resulting network is drawn with the tokens the facts produced. With an
  engine (see `WongiEngineWebui.Router`) it is read-only and shows that
  engine's network, rules and facts.
  """
  use WongiEngineWebuiWeb, :live_view

  alias WongiEngineWebui.Builder
  alias WongiEngineWebui.Codegen
  alias WongiEngineWebui.Network
  alias WongiEngineWebui.Reconstruct
  alias WongiEngineWebui.Spec
  alias WongiEngineWebui.Value
  alias WongiEngineWebuiWeb.FactComponents
  alias WongiEngineWebuiWeb.RuleComponents

  @node_types [
    {"join", "has"},
    {"negative", "neg"},
    {"filter", "filter"},
    {"assign", "assign"},
    {"aggregate", "aggregate"},
    {"ncc", "ncc"},
    {"any", "any"},
    {"production", "production"}
  ]

  @impl true
  def mount(_params, session, socket) do
    prefix = session["prefix"] || ""

    socket =
      socket
      |> assign(Layouts.asset_assigns(socket.endpoint, prefix))
      |> assign(
        live_socket_path: session["live_socket_path"] || "/live",
        engine_mfa: session["engine"],
        selected_rule: nil,
        selected_node: nil,
        node_types: @node_types
      )

    socket =
      case session["engine"] do
        nil ->
          assign(socket,
            mode: :editor,
            page_title: "Editor",
            tab: :rules,
            evaluate: evaluate?(session["evaluate"]),
            rules: initial_rules(session["initial_rules"]),
            facts: initial_facts(session["initial_facts"]),
            selected_rule: 0
          )

        _mfa ->
          assign(socket, mode: :readonly, page_title: "Engine", tab: :facts, evaluate: false)
      end

    {:ok, refresh(socket)}
  end

  defp evaluate?({m, f, a}), do: apply(m, f, a) == true
  defp evaluate?(flag), do: flag == true

  defp initial_rules(nil) do
    rule =
      Spec.new_rule("my_rule")
      |> Spec.append("clauses", %{
        Spec.new_clause("has")
        | s: Spec.var("x"),
          p: Spec.expr(":is_a"),
          o: Spec.expr(":person")
      })

    [rule]
  end

  # Rule specs are accepted as well as DSL rules, so that rules can be
  # restored with their code intact.
  defp initial_rules({m, f, a}) do
    for rule <- apply(m, f, a) do
      case rule do
        %Wongi.Engine.DSL.Rule{} -> Reconstruct.from_rule(rule)
        %{clauses: _} = spec -> Map.put_new(spec, :id, Spec.new_rule().id)
      end
    end
  end

  defp initial_facts(nil), do: []

  defp initial_facts({m, f, a}) do
    for {s, p, o} <- apply(m, f, a),
        do: Spec.new_fact(Value.to_source(s), Value.to_source(p), Value.to_source(o))
  end

  ## Compilation

  # Recomputes everything derived from the rules and facts (or the engine) and
  # pushes the graph to the client.
  defp refresh(%{assigns: %{mode: :editor, rules: rules, facts: facts}} = socket) do
    mode = if socket.assigns.evaluate, do: :evaluate, else: :safe
    errors = Enum.map(rules, &Builder.validate/1)

    fact_errors =
      facts
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {fact, index}, acc ->
        Map.merge(acc, Builder.validate_fact(fact, index, mode))
      end)

    state = %{
      engine: Wongi.Engine.new(),
      compiled: [],
      errors: errors,
      compile_errors: %{},
      fact_errors: fact_errors,
      facts_error: nil,
      asserted: []
    }

    {state, names, context_error} =
      case Builder.context(rules, mode) do
        {:ok, ctx} ->
          {state |> compile_rules(rules, ctx) |> assert_facts(facts, ctx), ctx.names, nil}

        {:error, message} ->
          {state, %{}, message}
      end

    invalid =
      state.errors
      |> Enum.with_index()
      |> Enum.reject(fn {errors, _index} -> errors == %{} end)
      |> MapSet.new(&elem(&1, 1))
      |> MapSet.union(MapSet.new(Map.keys(state.compile_errors)))

    socket
    |> assign(
      errors: state.errors,
      compile_errors: state.compile_errors,
      context_error: context_error,
      fact_errors: state.fact_errors,
      facts_error: state.facts_error,
      invalid: invalid,
      asserted: state.asserted,
      inferred: inferred(state.engine)
    )
    |> assign_forms()
    |> assign_code()
    |> push_graph(Network.build(state.engine, Enum.reverse(state.compiled), names: names))
  end

  defp refresh(%{assigns: %{mode: :readonly, engine_mfa: {m, f, a}}} = socket) do
    {engine, rules} =
      case apply(m, f, a) do
        {engine, rules} -> {engine, rules}
        engine -> {engine, []}
      end

    specs = Reconstruct.rules(engine, rules)

    labels =
      specs
      |> Enum.with_index()
      |> Enum.map(fn {{ref, spec}, index} ->
        {index, ref, RuleComponents.rule_label(spec, index)}
      end)

    asserted = engine.manual |> Enum.map(&triple/1) |> Enum.sort()

    socket
    |> assign(
      rules: Enum.map(specs, &elem(&1, 1)),
      invalid: MapSet.new(),
      asserted: asserted,
      inferred: inferred(engine)
    )
    |> assign_code()
    |> push_graph(Network.build(engine, labels))
  end

  defp compile_rules(state, rules, ctx) do
    rules
    |> Enum.with_index()
    |> Enum.reduce(state, fn {rule, index}, state ->
      if Enum.at(state.errors, index) == %{} do
        compile_rule(state, rule, index, ctx)
      else
        state
      end
    end)
  end

  defp compile_rule(state, rule, index, ctx) do
    {engine, ref} = Wongi.Engine.compile_and_get_ref(state.engine, Builder.to_rule(rule, ctx))
    label = RuleComponents.rule_label(rule, index)
    %{state | engine: engine, compiled: [{index, ref, label} | state.compiled]}
  rescue
    e in Builder.Error ->
      %{state | errors: List.update_at(state.errors, index, &Map.put(&1, e.path, e.message))}

    e ->
      %{state | compile_errors: Map.put(state.compile_errors, index, Exception.message(e))}
  end

  defp assert_facts(state, facts, ctx) do
    facts
    |> Enum.with_index()
    |> Enum.reduce(state, fn {fact, index}, state ->
      if Enum.any?([:s, :p, :o], &Map.has_key?(state.fact_errors, "facts.#{index}.#{&1}")),
        do: state,
        else: assert_fact(state, fact, index, ctx)
    end)
  end

  defp assert_fact(state, fact, index, ctx) do
    fact = Builder.to_fact(fact, index, ctx)
    engine = Wongi.Engine.assert(state.engine, fact)
    %{state | engine: engine, asserted: state.asserted ++ [triple(fact)]}
  rescue
    e in Builder.Error ->
      %{state | fact_errors: Map.put(state.fact_errors, e.path, e.message)}

    # Raised by rule code running as the fact propagates (evaluate mode).
    e ->
      %{state | facts_error: "fact #{index + 1}: " <> Exception.message(e)}
  end

  defp inferred(engine) do
    engine
    |> Wongi.Engine.select(:_, :_, :_)
    |> Enum.reject(&MapSet.member?(engine.manual, &1))
    |> Enum.map(&triple/1)
    |> Enum.sort()
  end

  defp triple({s, p, o}), do: {Value.to_source(s), Value.to_source(p), Value.to_source(o)}
  defp triple(wme), do: triple({wme.subject, wme.predicate, wme.object})

  defp assign_forms(%{assigns: %{rules: rules, selected_rule: index, facts: facts}} = socket) do
    form = if index, do: rules |> Enum.at(index) |> Spec.flatten() |> to_form(as: :rule)
    facts_form = %{facts: facts} |> Spec.flatten() |> to_form(as: :facts)
    assign(socket, form: form, facts_form: facts_form)
  end

  defp assign_code(%{assigns: %{rules: rules, asserted: asserted}} = socket) do
    code =
      Enum.map(rules, fn rule ->
        source = Codegen.rule(rule)
        %{source: source, html: Codegen.highlight(source)}
      end)

    facts_code =
      if asserted != [] do
        source = Codegen.facts(asserted)
        %{source: source, html: Codegen.highlight(source)}
      end

    assign(socket, code: code, facts_code: facts_code)
  end

  defp push_graph(socket, graph) do
    nodes = Map.new(graph.nodes, &{&1.id, &1})

    selected_node =
      case socket.assigns.selected_node do
        %{id: id} -> nodes[id]
        nil -> nil
      end

    socket
    |> assign(nodes: nodes, selected_node: selected_node)
    |> push_event("graph", graph)
    |> push_selection()
  end

  defp push_selection(socket) do
    push_event(socket, "select", %{
      rule: socket.assigns.selected_rule,
      node: socket.assigns.selected_node && socket.assigns.selected_node.id
    })
  end

  ## Events

  @impl true
  def handle_event("select_rule", %{"index" => index}, socket) do
    index = String.to_integer(index)

    # Clicking the selected rule's code in read-only mode deselects it.
    index =
      if socket.assigns.mode == :readonly and socket.assigns.selected_rule == index,
        do: nil,
        else: index

    socket
    |> assign(selected_rule: index)
    |> then(&if(&1.assigns.mode == :editor, do: assign_forms(&1), else: &1))
    |> push_selection()
    |> noreply()
  end

  def handle_event("select_node", %{"id" => id}, socket) do
    socket
    |> assign(selected_node: id && socket.assigns.nodes[id])
    |> push_selection()
    |> noreply()
  end

  def handle_event("tab", %{"tab" => tab}, socket) when tab in ~w(rules facts) do
    socket |> assign(tab: String.to_existing_atom(tab)) |> noreply()
  end

  def handle_event("reload", _params, %{assigns: %{mode: :readonly}} = socket) do
    socket |> refresh() |> put_flash(:info, "Engine reloaded") |> noreply()
  end

  def handle_event(_event, _params, %{assigns: %{mode: :readonly}} = socket),
    do: noreply(socket)

  def handle_event("change", %{"rule" => params}, socket) do
    update_rule(socket, &Spec.apply_params(&1, params))
  end

  def handle_event("add_clause", %{"path" => path, "type" => type}, socket) do
    if type in Spec.clause_types(),
      do: update_rule(socket, &Spec.append(&1, path, Spec.new_clause(type))),
      else: noreply(socket)
  end

  def handle_event("add_branch", %{"path" => path}, socket) do
    update_rule(socket, &Spec.append(&1, path <> ".branches", Spec.new_branch()))
  end

  def handle_event("add_action", %{"type" => type}, socket) do
    if type in Spec.action_types(),
      do: update_rule(socket, &Spec.append(&1, "actions", Spec.new_action(type))),
      else: noreply(socket)
  end

  def handle_event("remove", %{"path" => path}, socket) do
    update_rule(socket, &Spec.remove(&1, path))
  end

  def handle_event("move", %{"path" => path, "offset" => offset}, socket) do
    update_rule(socket, &Spec.move(&1, path, String.to_integer(offset)))
  end

  def handle_event("add_rule", _params, socket) do
    rules = socket.assigns.rules ++ [Spec.new_rule()]

    socket
    |> assign(rules: rules, selected_rule: length(rules) - 1)
    |> refresh()
    |> noreply()
  end

  def handle_event("delete_rule", %{"index" => index}, socket) do
    rules = List.delete_at(socket.assigns.rules, String.to_integer(index))
    selected = if rules == [], do: nil, else: min(socket.assigns.selected_rule, length(rules) - 1)

    socket
    |> assign(rules: rules, selected_rule: selected)
    |> refresh()
    |> noreply()
  end

  def handle_event("change_facts", %{"facts" => params}, socket) do
    update_facts(socket, &Spec.apply_params(%{facts: &1}, params).facts)
  end

  def handle_event("add_fact", _params, socket) do
    update_facts(socket, &(&1 ++ [Spec.new_fact()]))
  end

  def handle_event("remove_fact", %{"index" => index}, socket) do
    update_facts(socket, &List.delete_at(&1, String.to_integer(index)))
  end

  def handle_event("clear_facts", _params, socket) do
    update_facts(socket, fn _ -> [] end)
  end

  def handle_event("import_facts", %{"import" => %{"text" => text}}, socket) do
    case FactComponents.parse_import(text) do
      {:ok, facts} ->
        socket
        |> put_flash(:info, "Added #{length(facts)} fact(s)")
        |> update_facts(&(&1 ++ facts))

      {:error, message} ->
        socket |> put_flash(:error, message) |> noreply()
    end
  end

  defp update_rule(%{assigns: %{selected_rule: nil}} = socket, _fun), do: noreply(socket)

  defp update_rule(%{assigns: %{rules: rules, selected_rule: index}} = socket, fun) do
    socket
    |> assign(rules: List.update_at(rules, index, fun))
    |> refresh()
    |> noreply()
  end

  defp update_facts(socket, fun) do
    socket
    |> assign(facts: fun.(socket.assigns.facts))
    |> refresh()
    |> noreply()
  end

  defp noreply(socket), do: {:noreply, socket}

  ## Rendering

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      subtitle={if @mode == :editor, do: "Rule editor", else: "Read-only"}
    >
      <:actions>
        <span
          :if={@mode == :editor}
          id="evaluation-mode"
          class={["mode-badge", @evaluate && "mode-badge-warning"]}
          title={
            if @evaluate,
              do: "Code typed into the editor is evaluated on the server.",
              else:
                "Code is not evaluated: only literals and known pure functions take effect; other functions are stand-ins."
          }
        >
          <.icon name={if @evaluate, do: "hero-bolt-mini", else: "hero-shield-check-mini"} />
          {if @evaluate, do: "evaluating code", else: "safe mode"}
        </span>
        <button
          :if={@mode == :readonly}
          id="reload-engine"
          type="button"
          class="btn btn-ghost"
          phx-click="reload"
        >
          <.icon name="hero-arrow-path" /> Reload
        </button>
      </:actions>

      <div class="workspace">
        <aside id="editor" class="panel panel-editor">
          <nav class="panel-tabs" aria-label="Panels">
            <button
              :if={@mode == :editor}
              id="tab-rules"
              type="button"
              class={["panel-tab", @tab == :rules && "active"]}
              phx-click="tab"
              phx-value-tab="rules"
            >
              Rules <span class="panel-tab-count">{length(@rules)}</span>
            </button>
            <button
              id="tab-facts"
              type="button"
              class={["panel-tab", @tab == :facts && "active"]}
              phx-click="tab"
              phx-value-tab="facts"
            >
              Facts <span class="panel-tab-count">{length(@asserted) + length(@inferred)}</span>
            </button>
          </nav>

          <div :if={@tab == :rules} id="rules-panel">
            <p :if={@context_error} class="compile-error">
              <.icon name="hero-exclamation-triangle" /> {@context_error}
            </p>
            <RuleComponents.rule_tabs rules={@rules} selected={@selected_rule} invalid={@invalid} />
            <RuleComponents.rule_form
              :if={@selected_rule}
              form={@form}
              rule={Enum.at(@rules, @selected_rule)}
              index={@selected_rule}
              errors={Enum.at(@errors, @selected_rule)}
              compile_error={@compile_errors[@selected_rule]}
            />
            <div :if={@rules == []} class="empty-state">
              <p>No rules yet.</p>
            </div>
          </div>

          <FactComponents.facts_panel
            :if={@tab == :facts}
            editable={@mode == :editor}
            form={@mode == :editor && @facts_form}
            facts={if @mode == :editor, do: @facts, else: []}
            errors={if @mode == :editor, do: @fact_errors, else: %{}}
            facts_error={@mode == :editor && @facts_error}
            asserted={@asserted}
            inferred={@inferred}
          />
        </aside>

        <section class="panel panel-graph" aria-label="Rete network">
          <div id="rete-graph" class="graph" phx-hook="ReteGraph" phx-update="ignore"></div>
          <div class="graph-toolbar">
            <button
              type="button"
              class="icon-btn"
              title="Zoom in"
              phx-click={JS.dispatch("wongi:zoom", to: "#rete-graph", detail: %{factor: 1.25})}
            >
              <.icon name="hero-plus" />
            </button>
            <button
              type="button"
              class="icon-btn"
              title="Zoom out"
              phx-click={JS.dispatch("wongi:zoom", to: "#rete-graph", detail: %{factor: 0.8})}
            >
              <.icon name="hero-minus" />
            </button>
            <button
              type="button"
              class="icon-btn"
              title="Fit to view"
              phx-click={JS.dispatch("wongi:fit", to: "#rete-graph")}
            >
              <.icon name="hero-arrows-pointing-out" />
            </button>
          </div>
          <ul class="graph-legend">
            <li :for={{type, label} <- @node_types}>
              <span class={["type-dot", "node-#{type}"]} />{label}
            </li>
            <li class="legend-note">
              <span class="legend-count">3</span> tokens passed on
            </li>
          </ul>
        </section>

        <aside class="panel panel-side">
          <section :if={@selected_node} id="node-details" class="side-section node-details">
            <header class="side-header">
              <h2 class="section-title">
                <span class={["type-dot", "node-#{@selected_node.type}"]} />
                {@selected_node.title}
              </h2>
              <button
                type="button"
                class="icon-btn"
                title="Close"
                phx-click="select_node"
                phx-value-id=""
              >
                <.icon name="hero-x-mark-mini" />
              </button>
            </header>
            <pre :if={@selected_node.detail} class="code-block"><code>{Codegen.highlight(@selected_node.detail)}</code></pre>
            <p :if={@selected_node.stand_in} class="stand-in-note">
              <.icon name="hero-information-circle-mini" />
              Contains code that isn't evaluated in safe mode: functions are stand-ins
              (filters pass, actions do nothing) and other expressions match nothing.
            </p>
            <dl class="facts">
              <div>
                <dt>{if @selected_node.type == "production", do: "matches", else: "tokens in"}</dt>
                <dd>{@selected_node.tokens}</dd>
              </div>
              <div>
                <dt>used by</dt>
                <dd class="rule-links">
                  <button
                    :for={index <- @selected_node.rules}
                    type="button"
                    class={["chip", index == @selected_rule && "active"]}
                    phx-click="select_rule"
                    phx-value-index={index}
                  >
                    {RuleComponents.rule_label(Enum.at(@rules, index), index)}
                  </button>
                </dd>
              </div>
            </dl>
          </section>

          <section id="code" class="side-section code-section">
            <header class="side-header">
              <h2 class="section-title">Elixir</h2>
              <button
                id="copy-code"
                type="button"
                class="btn btn-ghost btn-small"
                phx-click={JS.dispatch("wongi:copy", to: "#code-source")}
              >
                <.icon name="hero-clipboard-document" /> Copy
              </button>
            </header>
            <pre class="code-block code-prelude"><code>{Codegen.highlight("use Wongi.Engine.DSL")}</code></pre>
            <div
              :for={{block, index} <- Enum.with_index(@code)}
              id={"code-rule-#{index}"}
              class={[
                "code-rule",
                index == @selected_rule && "active",
                MapSet.member?(@invalid, index) && "invalid"
              ]}
              phx-click="select_rule"
              phx-value-index={index}
            >
              <pre class="code-block"><code>{block.html}</code></pre>
            </div>
            <p :if={@code == []} class="empty-list">No rules.</p>
            <pre :if={@facts_code} id="code-facts" class="code-block code-facts"><code>{@facts_code.html}</code></pre>
            <textarea id="code-source" class="sr-only" readonly aria-hidden="true">{code_source(@code, @facts_code)}</textarea>
          </section>
        </aside>
      </div>
    </Layouts.app>
    """
  end

  defp code_source(code, facts_code) do
    blocks = ["use Wongi.Engine.DSL" | Enum.map(code, & &1.source)]
    blocks = if facts_code, do: blocks ++ [facts_code.source], else: blocks
    Enum.join(blocks, "\n\n")
  end
end
