defmodule WongiEngineWebui.Network do
  @moduledoc """
  Extracts the beta network of an engine as graph data for the client.

  Node ids are assigned breadth-first from the root, in node creation order,
  so the same rules always produce the same ids.
  """

  alias Wongi.Engine.Beta
  alias Wongi.Engine.Rete
  alias WongiEngineWebui.Codegen
  alias WongiEngineWebui.Reconstruct

  @type graph() :: %{nodes: [map()], edges: [map()]}

  @doc """
  Builds the graph of `engine`.

  `rules` lists `{index, production_ref, label}`; each node records the
  indices of the rules whose productions it leads to.
  """
  @spec build(Wongi.Engine.t(), [{non_neg_integer(), reference(), String.t()}]) :: graph()
  def build(engine, rules) do
    children = children(engine)
    order = bfs([Beta.ref(engine.beta_root)], children, MapSet.new(), [])
    ids = order |> Enum.with_index() |> Map.new(fn {ref, index} -> {ref, "n#{index}"} end)
    usage = usage(engine, rules)
    labels = Map.new(rules, fn {_index, ref, label} -> {ref, label} end)

    nodes =
      Enum.map(order, fn ref ->
        node = Rete.get_beta(engine, ref)
        {type, title, detail} = describe(node, labels)

        %{
          id: ids[ref],
          type: type,
          title: title,
          detail: detail,
          tokens: engine |> Rete.tokens(ref) |> MapSet.size(),
          rules: usage |> Map.get(ref, MapSet.new()) |> Enum.sort()
        }
      end)

    edges =
      Enum.flat_map(order, fn ref ->
        node = Rete.get_beta(engine, ref)

        parents =
          for parent <- Beta.parent_refs(node),
              do: %{source: ids[parent], target: ids[ref], kind: "beta"}

        case node do
          %Beta.NCC.Partner{ncc_ref: ncc} ->
            parents ++ [%{source: ids[ref], target: ids[ncc], kind: "partner"}]

          _ ->
            parents
        end
      end)

    %{nodes: nodes, edges: edges}
  end

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

  defp describe(%Beta.Root{}, _labels), do: {"root", "root", nil}
  defp describe(%Beta.NCC{}, _labels), do: {"ncc", "ncc", nil}
  defp describe(%Beta.NCC.Partner{}, _labels), do: {"ncc_partner", "ncc partner", nil}
  defp describe(%Beta.Or{}, _labels), do: {"any", "any", nil}

  defp describe(%Beta.Production{ref: ref}, labels),
    do: {"production", "production", Map.get(labels, ref, "rule")}

  defp describe(node, _labels) do
    clause = Reconstruct.node_clause(node)
    type = node.__struct__ |> Module.split() |> List.last() |> Macro.underscore()
    {type, title(clause), Codegen.clause(clause)}
  end

  defp title(%{type: "filter", op: op}), do: op
  defp title(%{type: "filter_fn"}), do: "filter"
  defp title(%{type: type}), do: type
end
