defmodule WongiEngineWebuiWeb.EngineLive do
  @moduledoc """
  The rule editor and network viewer.

  Without an engine in the session it is an editor: rules are edited as specs,
  compiled into a fresh engine on every change, and the resulting network is
  drawn. With an engine (see `WongiEngineWebui.Router`) it is read-only and
  shows that engine's network and rules.
  """
  use WongiEngineWebuiWeb, :live_view

  alias WongiEngineWebui.Builder
  alias WongiEngineWebui.Codegen
  alias WongiEngineWebui.Network
  alias WongiEngineWebui.Reconstruct
  alias WongiEngineWebui.Spec
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
          rules = initial_rules(session["initial_rules"])
          assign(socket, mode: :editor, page_title: "Editor", rules: rules, selected_rule: 0)

        _mfa ->
          assign(socket, mode: :readonly, page_title: "Engine")
      end

    {:ok, refresh(socket)}
  end

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

  defp initial_rules({m, f, a}), do: apply(m, f, a) |> Enum.map(&Reconstruct.from_rule/1)

  ## Compilation

  # Recomputes everything derived from the rules (or the engine) and pushes the
  # graph to the client.
  defp refresh(%{assigns: %{mode: :editor, rules: rules}} = socket) do
    errors = Enum.map(rules, &Builder.validate/1)

    {engine, compiled, compile_errors} =
      rules
      |> Enum.zip(errors)
      |> Enum.with_index()
      |> Enum.reduce({Wongi.Engine.new(), [], %{}}, fn
        {{rule, errors}, index}, {engine, compiled, compile_errors} when errors == %{} ->
          try do
            {engine, ref} = Wongi.Engine.compile_and_get_ref(engine, Builder.to_rule(rule))

            {engine, [{index, ref, RuleComponents.rule_label(rule, index)} | compiled],
             compile_errors}
          rescue
            e -> {engine, compiled, Map.put(compile_errors, index, Exception.message(e))}
          end

        _, acc ->
          acc
      end)

    invalid =
      errors
      |> Enum.with_index()
      |> Enum.reject(fn {errors, _index} -> errors == %{} end)
      |> Enum.map(&elem(&1, 1))
      |> MapSet.new()
      |> MapSet.union(MapSet.new(Map.keys(compile_errors)))

    socket
    |> assign(errors: errors, compile_errors: compile_errors, invalid: invalid)
    |> assign_form()
    |> assign_code()
    |> push_graph(Network.build(engine, Enum.reverse(compiled)))
  end

  defp refresh(%{assigns: %{mode: :readonly, engine_mfa: {m, f, a}}} = socket) do
    {engine, rules} =
      case apply(m, f, a) do
        {engine, rules} -> {engine, rules}
        engine -> {engine, []}
      end

    specs = Reconstruct.rules(engine, rules)
    rules = Enum.map(specs, &elem(&1, 1))

    labels =
      specs
      |> Enum.with_index()
      |> Enum.map(fn {{ref, spec}, index} ->
        {index, ref, RuleComponents.rule_label(spec, index)}
      end)

    socket
    |> assign(rules: rules, invalid: MapSet.new())
    |> assign_code()
    |> push_graph(Network.build(engine, labels))
  end

  defp assign_form(%{assigns: %{selected_rule: nil}} = socket), do: assign(socket, form: nil)

  defp assign_form(%{assigns: %{rules: rules, selected_rule: index}} = socket) do
    form = rules |> Enum.at(index) |> Spec.flatten() |> to_form(as: :rule)
    assign(socket, form: form)
  end

  defp assign_code(%{assigns: %{rules: rules}} = socket) do
    code =
      Enum.map(rules, fn rule ->
        source = Codegen.rule(rule)
        %{source: source, html: Codegen.highlight(source)}
      end)

    assign(socket, code: code)
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
    |> then(&if(&1.assigns.mode == :editor, do: assign_form(&1), else: &1))
    |> push_selection()
    |> noreply()
  end

  def handle_event("select_node", %{"id" => id}, socket) do
    socket
    |> assign(selected_node: id && socket.assigns.nodes[id])
    |> push_selection()
    |> noreply()
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

  defp update_rule(%{assigns: %{selected_rule: nil}} = socket, _fun), do: noreply(socket)

  defp update_rule(%{assigns: %{rules: rules, selected_rule: index}} = socket, fun) do
    socket
    |> assign(rules: List.update_at(rules, index, fun))
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

      <div class={["workspace", "workspace-#{@mode}"]}>
        <aside :if={@mode == :editor} id="editor" class="panel panel-editor">
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
            <dl class="facts">
              <div>
                <dt>tokens</dt>
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
            <textarea id="code-source" class="sr-only" readonly aria-hidden="true">{Enum.map_join(["use Wongi.Engine.DSL" | Enum.map(@code, & &1.source)], "\n\n", & &1)}</textarea>
          </section>
        </aside>
      </div>
    </Layouts.app>
    """
  end
end
