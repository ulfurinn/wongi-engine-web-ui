defmodule WongiEngineWebui.Expr do
  @moduledoc """
  An Elixir expression typed into the editor, kept as source text.

  Expressions are only ever parsed, never evaluated. Parsing goes through a
  static atoms encoder, so user input cannot create new atoms.

  When a rule is compiled for display, expressions stand in for the values they
  would produce: plain expressions become `%Expr{}` constants, and function
  expressions become placeholder functions of the same arity. The shape of the
  resulting Rete network does not depend on what those values actually are.
  Two placeholders compare equal when their sources are equal, so identical
  clauses still share nodes, as they would in a real engine.
  """

  defstruct [:source]

  @type t() :: %__MODULE__{source: String.t()}

  @doc """
  Parses `source`, returning its AST with atoms (including identifiers)
  encoded as `%WongiEngineWebui.Value.Atom{}`.
  """
  @spec parse(String.t()) :: {:ok, Macro.t()} | {:error, String.t()}
  def parse(source) when is_binary(source) do
    case String.trim(source) do
      "" ->
        {:error, "can't be blank"}

      trimmed ->
        case Code.string_to_quoted(trimmed,
               static_atoms_encoder: fn name, _meta ->
                 {:ok, %WongiEngineWebui.Value.Atom{name: name}}
               end,
               existing_atoms_only: true
             ) do
          {:ok, ast} -> {:ok, ast}
          {:error, {_meta, message, token}} -> {:error, format_error(message, token)}
        end
    end
  end

  defp format_error({prefix, suffix}, token), do: "#{prefix}#{token}#{suffix}"
  defp format_error(message, token), do: "#{message}#{token}"

  @doc """
  Returns the arity of the function `ast` denotes, or `nil` if it isn't a
  function literal (`fn` or a `&` capture).
  """
  @spec fn_arity(Macro.t()) :: non_neg_integer() | nil
  def fn_arity({:fn, _, [{:->, _, [args, _body]} | _]}), do: length(strip_guard(args))
  def fn_arity({:&, _, [{:/, _, [_fun, arity]}]}) when is_integer(arity), do: arity

  def fn_arity({:&, _, [body]}) do
    {_, max} =
      Macro.prewalk(body, 0, fn
        {:&, _, [n]} = node, acc when is_integer(n) -> {node, max(n, acc)}
        node, acc -> {node, acc}
      end)

    max
  end

  def fn_arity(_), do: nil

  defp strip_guard([{:when, _, args}]), do: Enum.drop(args, -1)
  defp strip_guard(args), do: args

  @doc """
  Returns the value `source` stands for at compile time: a placeholder
  function returning `result` if it is a function literal, an `%Expr{}`
  otherwise.
  """
  @spec stand_in(String.t(), any()) :: t() | function()
  def stand_in(source, result \\ nil) do
    source = String.trim(source)

    case parse(source) do
      {:ok, ast} ->
        case fn_arity(ast) do
          nil -> %__MODULE__{source: source}
          arity -> placeholder(arity, source, result)
        end

      {:error, _} ->
        %__MODULE__{source: source}
    end
  end

  @doc "Returns `true` for `%Expr{}` constants and placeholder functions."
  def stand_in?(value), do: source(value) != :error

  @doc "Returns the source of a placeholder function or `%Expr{}`, if it is one."
  @spec source(any()) :: {:ok, String.t()} | :error
  def source(%__MODULE__{source: source}), do: {:ok, source}

  def source(fun) when is_function(fun) do
    case Function.info(fun, :env) do
      {:env, [{__MODULE__, source, _result}]} -> {:ok, source}
      _ -> :error
    end
  end

  def source(_), do: :error

  # The tagged tuple is what `source/1` recognises in the closure's environment.
  defp placeholder(arity, source, result) do
    tag = {__MODULE__, source, result}

    case arity do
      0 -> fn -> elem(tag, 2) end
      1 -> fn _ -> elem(tag, 2) end
      2 -> fn _, _ -> elem(tag, 2) end
      3 -> fn _, _, _ -> elem(tag, 2) end
      _ -> %__MODULE__{source: source}
    end
  end
end
