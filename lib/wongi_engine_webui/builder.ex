defmodule WongiEngineWebui.Builder do
  @moduledoc """
  Validates rule specs and turns them into `Wongi.Engine.DSL` rules.

  See `context/2` for how values and variable names are produced.
  """

  import WongiEngineWebui.Spec, only: [filter_ops: 0]

  alias Wongi.Engine.Action.Generator
  alias Wongi.Engine.DSL
  alias Wongi.Engine.DSL.Var
  alias WongiEngineWebui.Builder.Error
  alias WongiEngineWebui.Expr
  alias WongiEngineWebui.Value

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

  @doc "Returns a map of path to error message for a fact; empty if it is valid."
  def validate_fact(fact, index, mode) do
    Enum.reduce([:s, :p, :o], %{}, fn field, errors ->
      path = "facts.#{index}.#{field}"

      case {Value.read(Map.fetch!(fact, field)), mode} do
        {{:error, message}, _} -> Map.put(errors, path, message)
        {:not_literal, :safe} -> Map.put(errors, path, "must be a literal value")
        _ -> errors
      end
    end)
  end

  ## Compilation

  @doc """
  The settings rules and facts are built with.

    * `mode` - `:safe` reads literals without evaluating anything and uses
      stand-ins for other code; `:evaluate` evaluates all code.
    * `vars` - variable names to the atoms they compile to. In safe mode
      these come from a fixed pool, so user input never creates atoms.
    * `names` - the reverse, from the atoms' names to the variable names.
  """
  defstruct mode: :safe, vars: %{}, names: %{}

  @var_pool for i <- 0..999, do: :"wongi_engine_webui_var_#{i}"

  @doc "Builds the context for a set of rule specs."
  @spec context([map()], :safe | :evaluate) :: {:ok, %__MODULE__{}} | {:error, String.t()}
  def context(rules, mode \\ :safe) do
    names = rules |> Enum.flat_map(&var_names/1) |> Enum.uniq() |> Enum.sort()

    vars =
      case mode do
        :safe when length(names) > length(@var_pool) -> :too_many
        :safe -> names |> Enum.zip(@var_pool) |> Map.new()
        :evaluate -> Map.new(names, &{&1, String.to_atom(&1)})
      end

    case vars do
      :too_many ->
        {:error, "too many distinct variables (at most #{length(@var_pool)})"}

      vars ->
        reverse = Map.new(vars, fn {name, atom} -> {Atom.to_string(atom), name} end)
        {:ok, %__MODULE__{mode: mode, vars: vars, names: reverse}}
    end
  end

  defp var_names(%{kind: "var", value: name}), do: [name]
  defp var_names(%{type: "filter_fn", var: var}), do: [var] |> Enum.reject(&(&1 == ""))
  defp var_names(%{type: "assign", name: name}), do: [name]

  defp var_names(%{type: "aggregate"} = c),
    do: [c.var, c.over | split_names(c.partition)] |> Enum.reject(&(&1 == ""))

  defp var_names(map) when is_map(map), do: map |> Map.values() |> Enum.flat_map(&var_names/1)
  defp var_names(list) when is_list(list), do: Enum.flat_map(list, &var_names/1)
  defp var_names(_), do: []

  @doc """
  Builds a `Wongi.Engine.DSL` rule from a valid spec. Raises
  `WongiEngineWebui.Builder.Error` if a value can't be built, which in
  evaluate mode includes errors raised by the code.
  """
  @spec to_rule(map(), %__MODULE__{} | nil) :: Wongi.Engine.DSL.Rule.t()
  def to_rule(rule, ctx \\ nil) do
    ctx = ctx || elem(context([rule]), 1)
    name = if rule.name == "", do: nil, else: rule.name

    DSL.rule(name,
      forall: list(rule.clauses, "clauses", ctx, &to_clause/3),
      do: list(rule.actions, "actions", ctx, &to_action/3)
    )
  end

  @doc "Builds a fact from a valid fact spec."
  def to_fact(fact, index, ctx) do
    {resolve(fact.s, "facts.#{index}.s", ctx, nil), resolve(fact.p, "facts.#{index}.p", ctx, nil),
     resolve(fact.o, "facts.#{index}.o", ctx, nil)}
  end

  defp list(items, path, ctx, fun) do
    items
    |> Enum.with_index()
    |> Enum.map(fn {item, index} -> fun.(item, "#{path}.#{index}", ctx) end)
  end

  defp to_clause(%{type: "has"} = c, path, ctx) do
    filters = list(Map.get(c, :when, []), path <> ".when", ctx, &to_clause/3)
    opts = if filters == [], do: [], else: [when: filters]

    DSL.has(
      term(c.s, path <> ".s", ctx),
      term(c.p, path <> ".p", ctx),
      term(c.o, path <> ".o", ctx),
      opts
    )
  end

  defp to_clause(%{type: "neg"} = c, path, ctx),
    do:
      DSL.neg(
        term(c.s, path <> ".s", ctx),
        term(c.p, path <> ".p", ctx),
        term(c.o, path <> ".o", ctx)
      )

  defp to_clause(%{type: "ncc"} = c, path, ctx),
    do: DSL.ncc(list(c.clauses, path <> ".clauses", ctx, &to_clause/3))

  defp to_clause(%{type: "any"} = c, path, ctx) do
    c.branches
    |> Enum.with_index()
    |> Enum.map(fn {branch, i} ->
      list(branch.clauses, "#{path}.branches.#{i}.clauses", ctx, &to_clause/3)
    end)
    |> DSL.any()
  end

  defp to_clause(%{type: "filter", op: op} = c, path, ctx) when op in @filter_ops do
    apply(DSL, String.to_existing_atom(op), [
      term(c.a, path <> ".a", ctx),
      term(c.b, path <> ".b", ctx)
    ])
  end

  defp to_clause(%{type: "filter_fn", var: "", code: code}, path, ctx),
    do: DSL.filter(resolve(code, path <> ".code", ctx, true))

  defp to_clause(%{type: "filter_fn", var: var, code: code}, path, ctx),
    do: DSL.filter(var(var, ctx), resolve(code, path <> ".code", ctx, true))

  defp to_clause(%{type: "assign"} = c, path, ctx),
    do: DSL.assign(var(c.name, ctx), resolve(c.value, path <> ".value", ctx, nil))

  defp to_clause(%{type: "aggregate"} = c, path, ctx) do
    source =
      if c.map == "",
        do: [over: ctx.vars[c.over]],
        else: [map: resolve(c.map, path <> ".map", ctx, nil)]

    partition =
      case split_names(c.partition) do
        [] -> []
        names -> [partition: Enum.map(names, &ctx.vars[&1])]
      end

    DSL.aggregate(resolve(c.fun, path <> ".fun", ctx, nil), var(c.var, ctx), source ++ partition)
  end

  defp to_action(%{type: "gen"} = a, path, ctx),
    do:
      DSL.gen(
        term(a.s, path <> ".s", ctx),
        term(a.p, path <> ".p", ctx),
        term(a.o, path <> ".o", ctx)
      )

  defp to_action(%{type: "code", code: code}, path, ctx) do
    case resolve(code, path <> ".code", ctx, []) do
      fun when is_function(fun, 1) -> Generator.new(fun)
      fun when is_function(fun, 2) or is_function(fun, 3) -> fun
      _ -> raise Error, path: path <> ".code", message: "expected a function of arity 1, 2 or 3"
    end
  end

  defp term(%{kind: "var", value: name}, _path, ctx), do: var(name, ctx)
  defp term(%{kind: "any"}, _path, _ctx), do: :_

  defp term(%{kind: "expr", value: source}, path, ctx),
    do: resolve(source, path <> ".value", ctx, nil)

  defp var(name, ctx), do: %Var{name: Map.fetch!(ctx.vars, name)}

  # The value of an expression field. `stand_in_result` is what a stand-in
  # function returns: something that lets tokens flow (filters pass,
  # generators produce nothing).
  defp resolve(source, path, %{mode: :evaluate}, _stand_in_result) do
    # Diagnostics are captured rather than logged: compile errors only say
    # "cannot compile file" otherwise, and warnings would go to the console.
    {result, diagnostics} =
      Code.with_diagnostics([log: false], fn ->
        try do
          {value, _binding} = Code.eval_string("use Wongi.Engine.DSL\n" <> source, [], file: path)
          {:ok, value}
        rescue
          e -> {:error, e}
        end
      end)

    case result do
      {:ok, value} ->
        value

      {:error, e} ->
        message =
          case Enum.find(diagnostics, &(&1.severity == :error)) do
            %{message: message} -> message
            nil -> Exception.message(e)
          end

        raise Error, path: path, message: message
    end
  end

  defp resolve(source, path, %{mode: :safe}, stand_in_result) do
    case Value.read(source) do
      {:ok, value} ->
        value

      {:error, message} ->
        raise Error, path: path, message: message

      :not_literal ->
        {:ok, ast} = Expr.parse(source)
        safe_capture(ast) || Expr.stand_in(source, stand_in_result)
    end
  end

  # Captures of pure functions that are safe to call on user data, by
  # `{module, name, arity}` (`nil` for functions in scope without a module).
  defp safe_capture({:&, _, [{:/, _, [fun, arity]}]}) when is_integer(arity) do
    case fun do
      {%Value.Atom{name: name}, _, context} when is_atom(context) ->
        safe_fun(nil, name, arity)

      {{:., _, [{:__aliases__, _, [%Value.Atom{name: module}]}, %Value.Atom{name: name}]}, _, []} ->
        safe_fun(module, name, arity)

      _ ->
        nil
    end
  end

  defp safe_capture(_ast), do: nil

  defp safe_fun(nil, "min", 1), do: &Wongi.Engine.Aggregates.min/1
  defp safe_fun(nil, "max", 1), do: &Wongi.Engine.Aggregates.max/1
  defp safe_fun(nil, "sum", 1), do: &Wongi.Engine.Aggregates.sum/1
  defp safe_fun(nil, "product", 1), do: &Wongi.Engine.Aggregates.product/1
  defp safe_fun(nil, "length", 1), do: &length/1
  defp safe_fun(nil, "is_atom", 1), do: &Value.atom?/1
  defp safe_fun(nil, "is_integer", 1), do: &is_integer/1
  defp safe_fun(nil, "is_float", 1), do: &is_float/1
  defp safe_fun(nil, "is_number", 1), do: &is_number/1
  defp safe_fun(nil, "is_binary", 1), do: &is_binary/1
  defp safe_fun(nil, "is_boolean", 1), do: &is_boolean/1
  defp safe_fun(nil, "is_list", 1), do: &is_list/1
  defp safe_fun(nil, "is_map", 1), do: &is_map/1
  defp safe_fun(nil, "is_nil", 1), do: &is_nil/1
  defp safe_fun("Enum", "count", 1), do: &Enum.count/1
  defp safe_fun("Enum", "sum", 1), do: &Enum.sum/1
  defp safe_fun("Enum", "min", 1), do: &Enum.min/1
  defp safe_fun("Enum", "max", 1), do: &Enum.max/1
  defp safe_fun("Enum", "uniq", 1), do: &Enum.uniq/1
  defp safe_fun("Enum", "sort", 1), do: &Enum.sort/1
  defp safe_fun(_module, _name, _arity), do: nil
end
