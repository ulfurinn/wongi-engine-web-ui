defmodule WongiEngineWebui.Spec do
  @moduledoc """
  The editable description of a rule.

  A spec is plain data (maps with atom keys, string leaves), so it can be
  flattened into a form, rebuilt from form params, and also produced from a
  compiled engine for read-only display.

      rule    :: %{id, name, clauses: [clause], actions: [action]}
      clause  :: %{type: "has" | "neg", s: term, p: term, o: term, when: [clause]}
               | %{type: "ncc", clauses: [clause]}
               | %{type: "any", branches: [%{clauses: [clause]}]}
               | %{type: "filter", op: op, a: term, b: term}
               | %{type: "filter_fn", var: name, code: source}
               | %{type: "assign", name: name, value: source}
               | %{type: "aggregate", fun: source, var: name, over: name,
                   map: source, partition: names}
      action  :: %{type: "gen", s: term, p: term, o: term}
               | %{type: "code", code: source}
      term    :: %{kind: "var" | "any" | "expr", value: String.t()}

  Paths address leaves and lists inside a rule as dot-separated segments, such
  as `"clauses.1.branches.0.clauses.2.s.value"`.
  """

  @clause_types ~w(has neg ncc any filter filter_fn assign aggregate)
  @action_types ~w(gen code)
  @filter_ops ~w(equal diff less lte greater gte in_list not_in_list)

  @keys ~w(name clauses actions branches facts type s p o kind value op a b var code fun over map partition when)a
  @key_lookup Map.new(@keys, &{Atom.to_string(&1), &1})

  def clause_types, do: @clause_types
  def action_types, do: @action_types
  def filter_ops, do: @filter_ops

  @doc "A new, empty rule."
  def new_rule(name \\ "") do
    %{id: unique_id(), name: name, clauses: [], actions: []}
  end

  @doc "A new clause of the given type, with blank fields."
  def new_clause(type)

  def new_clause(type) when type in ~w(has neg),
    do: %{type: type, s: var(), p: expr(), o: var(), when: []}

  def new_clause("ncc"), do: %{type: "ncc", clauses: []}
  def new_clause("any"), do: %{type: "any", branches: [new_branch(), new_branch()]}
  def new_clause("filter"), do: %{type: "filter", op: "equal", a: var(), b: expr()}
  def new_clause("filter_fn"), do: %{type: "filter_fn", var: "", code: "fn value -> true end"}
  def new_clause("assign"), do: %{type: "assign", name: "", value: ""}

  def new_clause("aggregate"),
    do: %{type: "aggregate", fun: "&min/1", var: "", over: "", map: "", partition: ""}

  @doc "A new action of the given type, with blank fields."
  def new_action("gen"), do: %{type: "gen", s: var(), p: expr(), o: var()}
  def new_action("code"), do: %{type: "code", code: "fn token -> [] end"}

  def new_branch, do: %{clauses: []}

  @doc "A fact spec: three Elixir literals (or expressions, when evaluating)."
  def new_fact(s \\ "", p \\ "", o \\ ""), do: %{s: s, p: p, o: o}

  @doc "A term spec."
  def var(name \\ ""), do: %{kind: "var", value: name}
  def any, do: %{kind: "any", value: ""}
  def expr(source \\ ""), do: %{kind: "expr", value: source}

  defp unique_id, do: System.unique_integer([:positive]) |> Integer.to_string()

  ## Paths

  @doc "Splits a path string into segments: integers for list indices, atoms for keys."
  @spec parse_path(String.t()) :: {:ok, list()} | :error
  def parse_path(path) when is_binary(path) do
    path
    |> String.split(".", trim: true)
    |> Enum.reduce_while({:ok, []}, fn segment, {:ok, acc} ->
      case {Integer.parse(segment), Map.fetch(@key_lookup, segment)} do
        {{index, ""}, _} -> {:cont, {:ok, [index | acc]}}
        {_, {:ok, key}} -> {:cont, {:ok, [key | acc]}}
        _ -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, segments} -> {:ok, Enum.reverse(segments)}
      :error -> :error
    end
  end

  @doc "Returns the value at `path`, or `nil`."
  def get(data, path) do
    case parse_path(path) do
      {:ok, segments} -> get_segments(data, segments)
      :error -> nil
    end
  end

  defp get_segments(data, []), do: data

  defp get_segments(list, [index | rest]) when is_list(list) and is_integer(index),
    do: list |> Enum.at(index) |> get_segments(rest)

  defp get_segments(map, [key | rest]) when is_map(map) and is_atom(key),
    do: map |> Map.get(key) |> get_segments(rest)

  defp get_segments(_, _), do: nil

  @doc """
  Applies `fun` to the value at `path`. Paths that don't exist in `data` are
  ignored, so stale form params can't create new structure.
  """
  def update(data, path, fun) do
    case parse_path(path) do
      {:ok, segments} -> update_segments(data, segments, fun)
      :error -> data
    end
  end

  defp update_segments(data, [], fun), do: fun.(data)

  defp update_segments(list, [index | rest], fun)
       when is_list(list) and is_integer(index) and index >= 0 and index < length(list),
       do: List.update_at(list, index, &update_segments(&1, rest, fun))

  defp update_segments(map, [key | rest], fun) when is_map(map) and is_map_key(map, key),
    do: Map.update!(map, key, &update_segments(&1, rest, fun))

  defp update_segments(data, _, _), do: data

  @doc "Sets the string leaf at `path`."
  def put_leaf(data, path, value) when is_binary(value) do
    update(data, path, fn
      old when is_binary(old) -> value
      old -> old
    end)
  end

  @doc "Appends `item` to the list at `path`."
  def append(data, path, item), do: update(data, path, &(&1 ++ [item]))

  @doc "Removes the list element `path` points at."
  def remove(data, path) do
    with {list_path, index} <- split_index(path) do
      update(data, list_path, &List.delete_at(&1, index))
    else
      _ -> data
    end
  end

  @doc "Moves the list element `path` points at by `offset` positions."
  def move(data, path, offset) do
    with {list_path, index} <- split_index(path) do
      update(data, list_path, fn list ->
        target = index + offset

        if target >= 0 and target < length(list) do
          {item, rest} = List.pop_at(list, index)
          List.insert_at(rest, target, item)
        else
          list
        end
      end)
    else
      _ -> data
    end
  end

  defp split_index(path) do
    {list_path, [last]} = path |> String.split(".") |> Enum.split(-1)

    case Integer.parse(last) do
      {index, ""} -> {Enum.join(list_path, "."), index}
      _ -> :error
    end
  end

  @doc "Flattens string leaves into a map of path to value, for forms."
  def flatten(data) do
    data
    |> Map.delete(:id)
    |> flatten("", %{})
  end

  defp flatten(value, path, acc) when is_binary(value), do: Map.put(acc, path, value)

  defp flatten(list, path, acc) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.reduce(acc, fn {item, index}, acc -> flatten(item, join(path, index), acc) end)
  end

  defp flatten(map, path, acc) when is_map(map) do
    Enum.reduce(map, acc, fn {key, value}, acc -> flatten(value, join(path, key), acc) end)
  end

  defp flatten(_, _, acc), do: acc

  defp join("", segment), do: to_string(segment)
  defp join(path, segment), do: "#{path}.#{segment}"

  @doc "Applies flat form params (path to value) to a rule."
  def apply_params(rule, params) when is_map(params) do
    Enum.reduce(params, rule, fn
      {path, value}, rule when is_binary(value) -> put_leaf(rule, path, value)
      _, rule -> rule
    end)
  end

  @doc """
  Applies `fun` to every variable name in a spec: variable terms and the
  name fields of filters, assignments and aggregates.
  """
  def map_var_names(%{kind: "var", value: name} = term, fun), do: %{term | value: fun.(name)}
  def map_var_names(%{type: "filter_fn"} = c, fun), do: %{c | var: map_optional(c.var, fun)}
  def map_var_names(%{type: "assign"} = c, fun), do: %{c | name: fun.(c.name)}

  def map_var_names(%{type: "aggregate"} = c, fun) do
    partition =
      c.partition
      |> String.split(",", trim: true)
      |> Enum.map_join(", ", &fun.(String.trim(&1)))

    %{c | var: fun.(c.var), over: map_optional(c.over, fun), partition: partition}
  end

  def map_var_names(map, fun) when is_map(map),
    do: Map.new(map, fn {key, value} -> {key, map_var_names(value, fun)} end)

  def map_var_names(list, fun) when is_list(list), do: Enum.map(list, &map_var_names(&1, fun))
  def map_var_names(other, _fun), do: other

  defp map_optional("", _fun), do: ""
  defp map_optional(name, fun), do: fun.(name)
end
