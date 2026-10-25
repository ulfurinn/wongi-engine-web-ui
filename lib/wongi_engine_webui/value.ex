defmodule WongiEngineWebui.Value do
  @moduledoc """
  Reads literal values from source without evaluating it, and renders values
  back as source.

  Literals are atoms, numbers, strings, `true`/`false`/`nil`, and lists,
  tuples and maps of literals. Atoms are read as `WongiEngineWebui.Value.Atom`
  structs unless real atoms are requested (in evaluate mode, where user code
  can create atoms anyway).
  """

  alias WongiEngineWebui.Codegen
  alias WongiEngineWebui.Expr
  alias WongiEngineWebui.Value.Atom

  @doc """
  Reads the literal in `source`. Returns `:not_literal` for valid code that
  isn't a literal, such as a function or a call.
  """
  @spec read(String.t(), keyword()) :: {:ok, term()} | :not_literal | {:error, String.t()}
  def read(source, opts \\ []) do
    with {:ok, ast} <- Expr.parse(source) do
      literal(ast, Keyword.get(opts, :atoms, :encoded))
    end
  end

  defp literal(value, _atoms)
       when is_number(value) or is_binary(value) or is_boolean(value) or is_nil(value),
       do: {:ok, value}

  defp literal(%Atom{name: name}, :encoded), do: {:ok, %Atom{name: name}}
  defp literal(%Atom{name: name}, :real), do: {:ok, String.to_atom(name)}

  defp literal({:-, _, [number]}, _atoms) when is_number(number), do: {:ok, -number}
  defp literal({:+, _, [number]}, _atoms) when is_number(number), do: {:ok, number}

  defp literal(list, atoms) when is_list(list), do: literals(list, atoms)

  defp literal({a, b}, atoms) do
    with {:ok, [a, b]} <- literals([a, b], atoms), do: {:ok, {a, b}}
  end

  defp literal({:{}, _, elements}, atoms) do
    with {:ok, elements} <- literals(elements, atoms), do: {:ok, List.to_tuple(elements)}
  end

  defp literal({:%{}, _, pairs}, atoms) do
    pairs
    |> Enum.reduce_while({:ok, %{}}, fn {key, value}, {:ok, map} ->
      with {:ok, key} <- literal(key, atoms),
           {:ok, value} <- literal(value, atoms) do
        {:cont, {:ok, Map.put(map, key, value)}}
      else
        other -> {:halt, other}
      end
    end)
  end

  defp literal(_ast, _atoms), do: :not_literal

  defp literals(list, atoms) do
    list
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case literal(item, atoms) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        other -> {:halt, other}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      other -> other
    end
  end

  @doc "Returns `true` for atoms, encoded or real."
  def atom?(%Atom{}), do: true
  def atom?(value), do: is_atom(value)

  @doc "Elixir source for a value, including encoded atoms and stand-ins."
  @spec to_source(term()) :: String.t()
  def to_source(%Atom{name: name}), do: Codegen.atom(name)
  def to_source(%Expr{source: source}), do: source

  def to_source(fun) when is_function(fun) do
    case Expr.source(fun) do
      {:ok, source} -> source
      :error -> WongiEngineWebui.Reconstruct.function_source(fun)
    end
  end

  def to_source(list) when is_list(list),
    do: "[" <> Enum.map_join(list, ", ", &to_source/1) <> "]"

  def to_source(tuple) when is_tuple(tuple),
    do: "{" <> (tuple |> Tuple.to_list() |> Enum.map_join(", ", &to_source/1)) <> "}"

  def to_source(%_{} = struct), do: inspect(struct, limit: 20, printable_limit: 120)

  def to_source(map) when is_map(map) do
    "%{" <>
      Enum.map_join(map, ", ", fn {k, v} -> to_source(k) <> " => " <> to_source(v) end) <> "}"
  end

  def to_source(value), do: inspect(value, limit: 20, printable_limit: 120)
end
