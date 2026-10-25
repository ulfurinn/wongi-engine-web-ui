defmodule WongiEngineWebui.Builder do
  @moduledoc """
  Validates rule specs and turns them into `Wongi.Engine.DSL` rules.

  Variable names stay strings (`%Var{name: "x"}`): the engine only uses them as
  token keys, and this way editing never creates atoms.
  """

  import WongiEngineWebui.Spec, only: [filter_ops: 0]

  alias Wongi.Engine.Action.Generator
  alias Wongi.Engine.DSL
  alias Wongi.Engine.DSL.Var
  alias WongiEngineWebui.Expr

  @identifier ~r/^[a-z_][a-zA-Z0-9_]*[?!]?$/
  @filter_ops WongiEngineWebui.Spec.filter_ops()

  @doc "Returns `true` if `name` can be written as a bare atom such as `:name`."
  def identifier?(name), do: Regex.match?(@identifier, name)

  ## Validation

  @doc "Returns a map of path to error message; empty if the rule is valid."
  @spec validate(map()) :: %{String.t() => String.t()}
  def validate(rule) do
    %{}
    |> check_optional_name("name", rule.name)
    |> check_clauses("clauses", rule.clauses)
    |> check_list("actions", rule.actions, &check_action/3)
  end

  defp check_clauses(errors, path, clauses),
    do: check_list(errors, path, clauses, &check_clause/3)

  defp check_list(errors, path, items, check) do
    items
    |> Enum.with_index()
    |> Enum.reduce(errors, fn {item, index}, errors ->
      check.(errors, "#{path}.#{index}", item)
    end)
  end

  defp check_clause(errors, path, %{type: type} = clause) when type in ~w(has neg) do
    errors
    |> check_term("#{path}.s", clause.s)
    |> check_term("#{path}.p", clause.p)
    |> check_term("#{path}.o", clause.o)
    |> check_clauses("#{path}.when", Map.get(clause, :when, []))
  end

  defp check_clause(errors, path, %{type: "ncc", clauses: clauses}) do
    errors
    |> check(path <> ".clauses", clauses != [], "add at least one clause")
    |> check_clauses(path <> ".clauses", clauses)
  end

  defp check_clause(errors, path, %{type: "any", branches: branches}) do
    branches
    |> Enum.with_index()
    |> Enum.reduce(check(errors, path, branches != [], "add at least one branch"), fn
      {branch, index}, errors ->
        check_clauses(errors, "#{path}.branches.#{index}.clauses", branch.clauses)
    end)
  end

  defp check_clause(errors, path, %{type: "filter"} = clause) do
    errors
    |> check(path <> ".op", clause.op in filter_ops(), "unknown filter")
    |> check_term("#{path}.a", clause.a)
    |> check_term("#{path}.b", clause.b)
  end

  defp check_clause(errors, path, %{type: "filter_fn"} = clause) do
    arities = if clause.var == "", do: [0, 1], else: [1]

    errors
    |> check_optional_name(path <> ".var", clause.var)
    |> check_fn(path <> ".code", clause.code, arities)
  end

  defp check_clause(errors, path, %{type: "assign"} = clause) do
    errors
    |> check_name(path <> ".name", clause.name)
    |> check_code(path <> ".value", clause.value)
  end

  defp check_clause(errors, path, %{type: "aggregate"} = clause) do
    errors
    |> check_fn(path <> ".fun", clause.fun, [1])
    |> check_name(path <> ".var", clause.var)
    |> check_aggregate_source(path, clause)
    |> check_names(path <> ".partition", clause.partition)
  end

  defp check_clause(errors, path, _clause), do: Map.put(errors, path, "unknown clause")

  defp check_aggregate_source(errors, path, %{over: "", map: ""}),
    do: Map.put(errors, path <> ".over", "set either over or map")

  defp check_aggregate_source(errors, path, %{over: over, map: ""}),
    do: check_name(errors, path <> ".over", over)

  defp check_aggregate_source(errors, path, %{over: "", map: map}),
    do: check_fn(errors, path <> ".map", map, [1])

  defp check_aggregate_source(errors, path, _),
    do: Map.put(errors, path <> ".map", "set only one of over and map")

  defp check_action(errors, path, %{type: "gen"} = action) do
    errors
    |> check_term("#{path}.s", action.s)
    |> check_term("#{path}.p", action.p)
    |> check_term("#{path}.o", action.o)
  end

  defp check_action(errors, path, %{type: "code", code: code}),
    do: check_fn(errors, path <> ".code", code, [1, 2, 3])

  defp check_action(errors, path, _action), do: Map.put(errors, path, "unknown action")

  defp check_term(errors, path, %{kind: "var", value: name}),
    do: check_name(errors, path <> ".value", name)

  defp check_term(errors, _path, %{kind: "any"}), do: errors

  defp check_term(errors, path, %{kind: "expr", value: source}),
    do: check_code(errors, path <> ".value", source)

  defp check_term(errors, path, _), do: Map.put(errors, path <> ".kind", "unknown kind")

  defp check_name(errors, path, ""), do: Map.put(errors, path, "can't be blank")

  defp check_name(errors, path, name),
    do: check(errors, path, identifier?(name), "not a valid name")

  defp check_optional_name(errors, _path, ""), do: errors
  defp check_optional_name(errors, path, name), do: check_name(errors, path, name)

  defp check_names(errors, path, names) do
    case split_names(names) |> Enum.reject(&identifier?/1) do
      [] -> errors
      [bad | _] -> Map.put(errors, path, "#{inspect(bad)} is not a valid name")
    end
  end

  defp check_code(errors, path, source) do
    case Expr.parse(source) do
      {:ok, _} -> errors
      {:error, message} -> Map.put(errors, path, message)
    end
  end

  defp check_fn(errors, path, source, arities) do
    with {:ok, ast} <- Expr.parse(source),
         arity when arity != nil <- Expr.fn_arity(ast),
         true <- arity in arities do
      errors
    else
      {:error, message} -> Map.put(errors, path, message)
      nil -> Map.put(errors, path, "expected a function")
      false -> Map.put(errors, path, "expected a function of arity #{Enum.join(arities, " or ")}")
    end
  end

  defp check(errors, _path, true, _message), do: errors
  defp check(errors, path, false, message), do: Map.put(errors, path, message)

  @doc false
  def split_names(names) do
    names |> String.split(",", trim: true) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  ## Compilation

  @doc "Builds a `Wongi.Engine.DSL` rule from a valid spec."
  @spec to_rule(map()) :: Wongi.Engine.DSL.Rule.t()
  def to_rule(rule) do
    name = if rule.name == "", do: nil, else: rule.name

    DSL.rule(name,
      forall: Enum.map(rule.clauses, &to_clause/1),
      do: Enum.map(rule.actions, &to_action/1)
    )
  end

  defp to_clause(%{type: "has"} = c) do
    filters = Enum.map(Map.get(c, :when, []), &to_clause/1)
    opts = if filters == [], do: [], else: [when: filters]
    DSL.has(to_value(c.s), to_value(c.p), to_value(c.o), opts)
  end

  defp to_clause(%{type: "neg"} = c), do: DSL.neg(to_value(c.s), to_value(c.p), to_value(c.o))
  defp to_clause(%{type: "ncc"} = c), do: DSL.ncc(Enum.map(c.clauses, &to_clause/1))

  defp to_clause(%{type: "any"} = c),
    do: DSL.any(Enum.map(c.branches, fn branch -> Enum.map(branch.clauses, &to_clause/1) end))

  defp to_clause(%{type: "filter", op: op} = c) when op in @filter_ops do
    apply(DSL, String.to_existing_atom(op), [to_value(c.a), to_value(c.b)])
  end

  defp to_clause(%{type: "filter_fn", var: "", code: code}),
    do: DSL.filter(Expr.stand_in(code, true))

  defp to_clause(%{type: "filter_fn", var: var, code: code}),
    do: DSL.filter(%Var{name: var}, Expr.stand_in(code, true))

  defp to_clause(%{type: "assign"} = c),
    do: DSL.assign(%Var{name: c.name}, Expr.stand_in(c.value))

  defp to_clause(%{type: "aggregate"} = c) do
    source = if c.map == "", do: [over: c.over], else: [map: Expr.stand_in(c.map)]

    partition =
      case split_names(c.partition) do
        [] -> []
        names -> [partition: names]
      end

    DSL.aggregate(Expr.stand_in(c.fun), %Var{name: c.var}, source ++ partition)
  end

  defp to_action(%{type: "gen"} = a), do: DSL.gen(to_value(a.s), to_value(a.p), to_value(a.o))

  defp to_action(%{type: "code", code: code}) do
    case Expr.stand_in(code, []) do
      fun when is_function(fun, 1) -> Generator.new(fun)
      fun -> fun
    end
  end

  defp to_value(%{kind: "var", value: name}), do: %Var{name: name}
  defp to_value(%{kind: "any"}), do: :_
  defp to_value(%{kind: "expr", value: source}), do: %Expr{source: String.trim(source)}
end
