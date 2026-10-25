defmodule WongiEngineWebui.Reconstruct do
  @moduledoc """
  Recovers rule specs from compiled engines, for read-only display.

  A compiled engine keeps every node of its Rete network, but not the rules
  themselves. Each rule is rebuilt by walking from its production node back to
  the root. The result is equivalent to the original rule, but rule names,
  the order of `any` branches, and the source of anonymous functions are lost.
  When the original `Wongi.Engine.DSL.Rule` structs are available, they are
  used instead.
  """

  alias Wongi.Engine.Action.Generator
  alias Wongi.Engine.Beta
  alias Wongi.Engine.DSL
  alias Wongi.Engine.DSL.Var
  alias Wongi.Engine.Filter
  alias WongiEngineWebui.Expr
  alias WongiEngineWebui.Spec

  @filter_ops %{
    Filter.Equal => "equal",
    Filter.Diff => "diff",
    Filter.Less => "less",
    Filter.LTE => "lte",
    Filter.Greater => "greater",
    Filter.GTE => "gte",
    Filter.InList => "in_list",
    Filter.NotInList => "not_in_list"
  }

  @doc """
  Returns `{production_ref, spec}` for every rule in `engine`.

  Rules given in `rules` come first, in that order, and are rendered from
  their definitions. The remaining productions are reconstructed from the
  network, in the order their nodes were created.
  """
  @spec rules(Wongi.Engine.t(), [DSL.Rule.t()]) :: [{reference(), map()}]
  def rules(engine, rules \\ []) do
    productions = Wongi.Engine.productions(engine)

    known =
      for %DSL.Rule{ref: ref} = rule <- rules, MapSet.member?(productions, ref) do
        {ref, from_rule(rule)}
      end

    known_refs = MapSet.new(known, &elem(&1, 0))

    unknown =
      productions
      |> Enum.reject(&MapSet.member?(known_refs, &1))
      |> Enum.sort()
      |> Enum.map(&{&1, from_production(engine, &1)})

    known ++ unknown
  end

  ## From DSL structs

  @doc "Converts a `Wongi.Engine.DSL.Rule` into a spec."
  def from_rule(%DSL.Rule{} = rule) do
    %{
      Spec.new_rule(name(rule.name))
      | clauses: Enum.map(rule.forall, &dsl_clause/1),
        actions: Enum.map(rule.actions, &action/1)
    }
  end

  defp dsl_clause(%DSL.Has{} = c) do
    filters = c.filters |> List.wrap() |> Enum.map(&filter/1)
    %{type: "has", s: term(c.subject), p: term(c.predicate), o: term(c.object), when: filters}
  end

  defp dsl_clause(%DSL.Neg{} = c),
    do: %{type: "neg", s: term(c.subject), p: term(c.predicate), o: term(c.object), when: []}

  defp dsl_clause(%DSL.NCC{subchain: subchain}),
    do: %{type: "ncc", clauses: Enum.map(subchain, &dsl_clause/1)}

  defp dsl_clause(%DSL.Any{clauses: branches}),
    do: %{
      type: "any",
      branches: Enum.map(branches, &%{clauses: Enum.map(&1, fn c -> dsl_clause(c) end)})
    }

  defp dsl_clause(%DSL.Filter{filter: f}), do: filter(f)
  defp dsl_clause(%DSL.Assign{name: name, value: value}), do: assign(name, value)
  defp dsl_clause(%DSL.Aggregate{fun: fun, var: var, opts: opts}), do: aggregate(fun, var, opts)

  defp dsl_clause(other),
    do: %{type: "filter_fn", var: "", code: "# unsupported clause: " <> inspect(other)}

  ## From the network

  @doc "Reconstructs the spec of the rule ending in the production `ref`."
  def from_production(engine, ref) do
    production = Wongi.Engine.Rete.get_beta(engine, ref)

    %{
      Spec.new_rule()
      | clauses: chain(engine, production.parent_ref, root_ref(engine)),
        actions: Enum.map(production.actions, &action/1)
    }
  end

  @doc """
  The clause a single network node stands for. NCC and `any` nodes come back
  without their sub-chains.
  """
  def node_clause(%Beta.Join{} = node) do
    filters = node.filters |> List.wrap() |> Enum.map(&filter/1)
    Map.put(template_clause("has", node), :when, filters)
  end

  def node_clause(%Beta.Negative{} = node), do: Map.put(template_clause("neg", node), :when, [])
  def node_clause(%Beta.Filter{filter: f}), do: filter(f)
  def node_clause(%Beta.Assign{name: name, value: value}), do: assign(name, value)
  def node_clause(%Beta.Aggregate{fun: fun, var: var, opts: opts}), do: aggregate(fun, var, opts)
  def node_clause(%Beta.NCC{}), do: %{type: "ncc", clauses: []}
  def node_clause(%Beta.Or{}), do: %{type: "any", branches: []}
  def node_clause(_), do: nil

  # Clauses for the nodes from `ref` up to, but excluding, `stop`, root first.
  defp chain(_engine, stop, stop), do: []

  defp chain(engine, ref, stop) do
    case get(engine, ref) do
      %Beta.NCC{parent_ref: parent, partner_ref: partner_ref} ->
        partner = get(engine, partner_ref)
        clause = %{type: "ncc", clauses: chain(engine, partner.parent_ref, parent)}
        chain(engine, parent, stop) ++ [clause]

      %Beta.Or{parent_refs: parents} ->
        parents = Enum.sort(parents)
        fork = nearest_common_ancestor(engine, parents)
        branches = Enum.map(parents, &%{clauses: chain(engine, &1, fork)})
        chain(engine, fork, stop) ++ [%{type: "any", branches: branches}]

      %Beta.Root{} ->
        []

      node ->
        chain(engine, node.parent_ref, stop) ++ [node_clause(node)]
    end
  end

  defp nearest_common_ancestor(engine, refs) do
    common =
      refs
      |> Enum.map(&ancestors(engine, &1))
      |> Enum.reduce(&MapSet.intersection/2)

    Enum.max_by(common, &depth(engine, &1))
  end

  # A node and everything above it.
  defp ancestors(engine, ref) do
    engine
    |> get(ref)
    |> Beta.parent_refs()
    |> Enum.reduce(MapSet.new([ref]), &MapSet.union(&2, ancestors(engine, &1)))
  end

  defp depth(engine, ref) do
    case engine |> get(ref) |> Beta.parent_refs() |> Enum.to_list() do
      [] -> 0
      parents -> 1 + (parents |> Enum.map(&depth(engine, &1)) |> Enum.max())
    end
  end

  defp root_ref(engine), do: Beta.ref(engine.beta_root)
  defp get(engine, ref), do: Wongi.Engine.Rete.get_beta(engine, ref)

  defp template_clause(type, %{template: template, tests: tests, assignments: assignments}) do
    field = fn field ->
      case Map.get(tests, field) || Map.get(assignments, field) do
        nil -> term(template[field])
        var -> Spec.var(name(var))
      end
    end

    %{type: type, s: field.(:subject), p: field.(:predicate), o: field.(:object)}
  end

  ## Shared

  defp filter(%DSL.Filter{filter: f}), do: filter(f)

  defp filter(%Filter.Function{var: var, func: func}),
    do: %{type: "filter_fn", var: var_name(var), code: source(func)}

  defp filter(%module{a: a, b: b}) when is_map_key(@filter_ops, module),
    do: %{type: "filter", op: @filter_ops[module], a: term(a), b: term(b)}

  defp filter(other), do: %{type: "filter_fn", var: "", code: source(other)}

  defp assign(name, value), do: %{type: "assign", name: var_name(name), value: source(value)}

  defp aggregate(fun, var, opts) do
    partition = opts |> Keyword.get(:partition) |> List.wrap() |> Enum.map_join(", ", &var_name/1)

    %{
      type: "aggregate",
      fun: source(fun),
      var: var_name(var),
      over: opts |> Keyword.get(:over) |> var_name(),
      map: if(opts[:map], do: source(opts[:map]), else: ""),
      partition: partition
    }
  end

  defp action(%Generator{template: nil, generator: fun}), do: %{type: "code", code: source(fun)}

  defp action(%Generator{template: t}),
    do: %{type: "gen", s: term(t.subject), p: term(t.predicate), o: term(t.object)}

  defp action(other), do: %{type: "code", code: source(other)}

  defp term(%Var{name: name}), do: Spec.var(name(name))
  defp term(:_), do: Spec.any()
  defp term(value), do: Spec.expr(source(value))

  defp var_name(nil), do: ""
  defp var_name(%Var{name: name}), do: name(name)
  defp var_name(name), do: name(name)

  defp name(nil), do: ""
  defp name(name) when is_atom(name), do: Atom.to_string(name)
  defp name(name) when is_binary(name), do: name
  defp name(name), do: inspect(name)

  @doc """
  Elixir source for a runtime value. Anonymous functions can't be recovered
  and are shown as `fn ... -> ... end` of the right arity.
  """
  def source(value) do
    case Expr.source(value) do
      {:ok, source} -> source
      :error -> value_source(value)
    end
  end

  defp value_source(fun) when is_function(fun) do
    info = Function.info(fun)

    case info[:type] do
      :external ->
        "&#{qualifier(info[:module], info[:name], info[:arity])}#{info[:name]}/#{info[:arity]}"

      :local ->
        args = List.duplicate(" _", info[:arity]) |> Enum.join(",")
        "fn#{args} -> ... end"
    end
  end

  defp value_source(value), do: inspect(value, limit: 20, printable_limit: 120)

  # Functions in scope under `use Wongi.Engine.DSL` are written unqualified.
  defp qualifier(Wongi.Engine.Aggregates, _name, _arity), do: ""

  defp qualifier(:erlang, name, arity) do
    if function_exported?(Kernel, name, arity) or macro_exported?(Kernel, name, arity),
      do: "",
      else: ":erlang."
  end

  defp qualifier(module, _name, _arity), do: inspect(module) <> "."
end
