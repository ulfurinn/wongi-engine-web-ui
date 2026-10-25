defmodule WongiEngineWebui.Codegen do
  @moduledoc """
  Renders rule specs as `Wongi.Engine.DSL` source code.

  The output assumes `use Wongi.Engine.DSL` is in scope.
  """

  alias WongiEngineWebui.Builder

  @doc "The source of a whole rule, formatted when it parses."
  @spec rule(map()) :: String.t()
  def rule(spec) do
    forall = "forall: [" <> Enum.map_join(spec.clauses, ", ", &clause/1) <> "]"
    actions = "do: [" <> Enum.map_join(spec.actions, ", ", &action/1) <> "]"

    args =
      case spec.name do
        "" -> [forall, actions]
        name -> [atom(name), forall, actions]
      end

    format("rule(" <> Enum.join(args, ", ") <> ")")
  end

  @doc "The source of a single clause, unformatted."
  @spec clause(map()) :: String.t()
  def clause(%{type: type} = c) when type in ~w(has neg) do
    filters =
      case Map.get(c, :when, []) do
        [] -> []
        filters -> ["when: [" <> Enum.map_join(filters, ", ", &clause/1) <> "]"]
      end

    call(type, [term(c.s), term(c.p), term(c.o) | filters])
  end

  def clause(%{type: "ncc", clauses: clauses}), do: call("ncc", [list(clauses)])

  def clause(%{type: "any", branches: branches}),
    do: call("any", ["[" <> Enum.map_join(branches, ", ", &list(&1.clauses)) <> "]"])

  def clause(%{type: "filter", op: op} = c), do: call(op, [term(c.a), term(c.b)])
  def clause(%{type: "filter_fn", var: "", code: code}), do: call("filter", [src(code)])

  def clause(%{type: "filter_fn", var: var, code: code}),
    do: call("filter", [atom(var), src(code)])

  def clause(%{type: "assign", name: name, value: value}),
    do: call("assign", [atom(name), src(value)])

  def clause(%{type: "aggregate"} = c) do
    source = if c.map == "", do: ["over: " <> atom(c.over)], else: ["map: " <> src(c.map)]

    partition =
      case Builder.split_names(c.partition) do
        [] -> []
        [name] -> ["partition: " <> atom(name)]
        names -> ["partition: [" <> Enum.map_join(names, ", ", &atom/1) <> "]"]
      end

    call("aggregate", [src(c.fun), atom(c.var)] ++ source ++ partition)
  end

  @doc "The source of a single action, unformatted."
  @spec action(map()) :: String.t()
  def action(%{type: "gen"} = a), do: call("gen", [term(a.s), term(a.p), term(a.o)])

  def action(%{type: "code", code: code}) do
    with {:ok, ast} <- WongiEngineWebui.Expr.parse(code),
         1 <- WongiEngineWebui.Expr.fn_arity(ast) do
      call("gen", [code])
    else
      _ -> src(code)
    end
  end

  @doc "The source of a term."
  def term(%{kind: "var", value: name}), do: "var(" <> atom(name) <> ")"
  def term(%{kind: "any"}), do: ":_"
  def term(%{kind: "expr", value: source}), do: src(source)

  @doc "Writes a name as an atom literal without creating the atom."
  def atom(""), do: "..."

  def atom(name) do
    if Builder.identifier?(name), do: ":" <> name, else: ":" <> inspect(name)
  end

  # Blank fields are written as `...`, which keeps the code parseable (and so
  # formattable) while the rule is being filled in.
  defp src(source) do
    case String.trim(source) do
      "" -> "..."
      trimmed -> trimmed
    end
  end

  defp list(clauses), do: "[" <> Enum.map_join(clauses, ", ", &clause/1) <> "]"
  defp call(fun, args), do: fun <> "(" <> Enum.join(args, ", ") <> ")"

  @doc "Formats `source`, returning it unchanged if it doesn't parse."
  def format(source, opts \\ []) do
    source
    |> Code.format_string!(Keyword.put_new(opts, :line_length, 60))
    |> IO.iodata_to_binary()
  rescue
    _ -> source
  end

  @doc "Syntax-highlighted HTML for `source`, without the surrounding `<pre>`."
  def highlight(source) do
    source
    |> Makeup.highlight_inner_html(lexer: Makeup.Lexers.ElixirLexer)
    |> Phoenix.HTML.raw()
  end
end
