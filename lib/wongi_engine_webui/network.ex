defmodule WongiEngineWebui.Network do
  @moduledoc """
  Extracts the beta network of an engine as graph data for the client.

  Node ids are assigned breadth-first from the root, in node creation order,
  so the same rules always produce the same ids.

  Each node stores the tokens (partial matches) its parent passed to it.
  Edges carry the number of tokens that went along them, and production
  nodes the number of times their rule matched. Nodes holding stand-ins for
  code that wasn't evaluated are flagged.
  """

  alias Wongi.Engine.Beta
  alias Wongi.Engine.Rete
  alias WongiEngineWebui.Codegen
  alias WongiEngineWebui.Reconstruct
  alias WongiEngineWebui.Spec

  @type graph() :: %{nodes: [map()], edges: [map()]}

  @doc """
  Builds the graph of `engine`.

  `rules` lists `{index, production_ref, label}`; each node records the
  indices of the rules whose productions it leads to.

  ## Options

    * `:names` - maps variable names as compiled to the names to display
      (see `WongiEngineWebui.Builder.context/2`).
  """
  @spec build(Wongi.Engine.t(), [{non_neg_integer(), reference(), String.t()}], keyword()) ::
          graph()
  def build(engine, rules, opts \\ []) do
    names = Keyword.get(opts, :names, %{})
    root = Beta.ref(engine.beta_root)
    children = children(engine)
    order = bfs([Beta.ref(engine.beta_root)], children, MapSet.new(), [])
    ids = order |> Enum.with_index() |> Map.new(fn {ref, index} -> {ref, "n#{index}"} end)
    usage = usage(engine, rules)
    labels = Map.new(rules, fn {_index, ref, label} -> {ref, label} end)

    nodes =
      Enum.map(order, fn ref ->
        node = Rete.get_beta(engine, ref)
        {type, title, detail} = describe(node, labels, names)

        %{
          id: ids[ref],
          type: type,
          title: title,
          detail: detail,
          tokens: engine |> Rete.tokens(ref) |> MapSet.size(),
          stand_in: stand_in?(node),
          rules: usage |> Map.get(ref, MapSet.new()) |> Enum.sort()
        }
      end)

    edges =
      Enum.flat_map(order, fn ref ->
        node = Rete.get_beta(engine, ref)

        parents =
          for parent <- Beta.parent_refs(node) do
            count = if parent == root, do: nil, else: passed(engine, parent, ref)
            %{source: ids[parent], target: ids[ref], kind: "beta", count: count}
          end

        case node do
          %Beta.NCC.Partner{ncc_ref: ncc} ->
            parents ++ [%{source: ids[ref], target: ids[ncc], kind: "partner", count: nil}]

          _ ->
            parents
        end
      end)

    %{nodes: nodes, edges: edges}
  end

  # Tokens at `child` that came from `parent`.
  defp passed(engine, parent, child) do
    engine
    |> Rete.tokens(child)
    |> Enum.count(fn token -> Enum.any?(token.parents, &(&1.node_ref == parent)) end)
  end

  defp stand_in?(node) do
    node
    |> Map.from_struct()
    |> Map.values()
    |> Enum.any?(&contains_stand_in?/1)
  end

  defp contains_stand_in?(value) when is_function(value),
    do: WongiEngineWebui.Expr.stand_in?(value)

  defp contains_stand_in?(%WongiEngineWebui.Expr{}), do: true

  defp contains_stand_in?(%_{} = struct),
    do: struct |> Map.from_struct() |> Map.values() |> Enum.any?(&contains_stand_in?/1)

  defp contains_stand_in?(map) when is_map(map),
    do: map |> Map.values() |> Enum.any?(&contains_stand_in?/1)

  defp contains_stand_in?(list) when is_list(list), do: Enum.any?(list, &contains_stand_in?/1)

  defp contains_stand_in?(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.any?(&contains_stand_in?/1)

  defp contains_stand_in?(_), do: false

  defp children(engine) do
    Map.new(engine.beta_subscriptions, fn {parent, children} ->
      {parent, Enum.reverse(children)}
    end)
  end

  defp bfs([], _children, _seen, acc), do: Enum.reverse(acc)

  defp bfs([ref | rest], children, seen, acc) do
    if MapSet.member?(seen, ref) do
      bfs(rest, children, seen, acc)
    else
      bfs(rest ++ Map.get(children, ref, []), children, MapSet.put(seen, ref), [ref | acc])
    end
  end

  # Rule indices by node: everything a production depends on, including NCC
  # partner chains.
  defp usage(engine, rules) do
    Enum.reduce(rules, %{}, fn {index, ref, _label}, usage ->
      engine
      |> dependencies(ref, MapSet.new())
      |> Enum.reduce(usage, fn dep, usage ->
        Map.update(usage, dep, MapSet.new([index]), &MapSet.put(&1, index))
      end)
    end)
  end

  defp dependencies(engine, ref, seen) do
    if MapSet.member?(seen, ref) do
      seen
    else
      node = Rete.get_beta(engine, ref)
      seen = MapSet.put(seen, ref)

      extra =
        case node do
          %Beta.NCC{partner_ref: partner} -> [partner]
          _ -> []
        end

      Enum.reduce(
        Enum.to_list(Beta.parent_refs(node)) ++ extra,
        seen,
        &dependencies(engine, &1, &2)
      )
    end
  end

  defp describe(%Beta.Root{}, _labels, _names), do: {"root", "root", nil}
  defp describe(%Beta.NCC{}, _labels, _names), do: {"ncc", "ncc", nil}
  defp describe(%Beta.NCC.Partner{}, _labels, _names), do: {"ncc_partner", "ncc partner", nil}
  defp describe(%Beta.Or{}, _labels, _names), do: {"any", "any", nil}

  defp describe(%Beta.Production{ref: ref}, labels, _names),
    do: {"production", "production", Map.get(labels, ref, "rule")}

  defp describe(node, _labels, names) do
    clause =
      node
      |> Reconstruct.node_clause()
      |> Spec.map_var_names(&Map.get(names, &1, &1))

    type = node.__struct__ |> Module.split() |> List.last() |> Macro.underscore()
    {type, title(clause), Codegen.clause(clause)}
  end

  defp title(%{type: "filter", op: op}), do: op
  defp title(%{type: "filter_fn"}), do: "filter"
  defp title(%{type: type}), do: type
end
