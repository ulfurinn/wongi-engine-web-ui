defmodule WongiEngineWebui.BuilderTest do
  use ExUnit.Case, async: true

  alias WongiEngineWebui.Builder
  alias WongiEngineWebui.Example
  alias WongiEngineWebui.Network
  alias WongiEngineWebui.Reconstruct
  alias WongiEngineWebui.Spec

  test "validate/1 reports errors by path" do
    rule =
      Spec.new_rule("Bad Name")
      |> Spec.append("clauses", Spec.new_clause("has"))
      |> Spec.append("clauses", %{Spec.new_clause("filter_fn") | code: ":not_a_fn"})
      |> Spec.append("clauses", Spec.new_clause("ncc"))
      |> Spec.append("actions", %{Spec.new_action("code") | code: "fn -> nil end"})

    assert Builder.validate(rule) == %{
             "name" => "not a valid name",
             "clauses.0.s.value" => "can't be blank",
             "clauses.0.p.value" => "can't be blank",
             "clauses.0.o.value" => "can't be blank",
             "clauses.1.code" => "expected a function",
             "clauses.2.clauses" => "add at least one clause",
             "actions.0.code" => "expected a function of arity 1 or 2 or 3"
           }
  end

  test "rules built from specs produce the same network as the originals" do
    rules = Example.rules()
    specs = Enum.map(rules, &Reconstruct.from_rule/1)

    assert Enum.all?(specs, &(Builder.validate(&1) == %{}))

    {:ok, ctx} = Builder.context(specs)
    built = Enum.map(specs, &Builder.to_rule(&1, ctx))
    assert graph(built, names: ctx.names) == graph(rules)
  end

  test "safe mode never creates atoms for variable names" do
    name = "never_seen_#{System.unique_integer([:positive])}"

    rule = %{
      Spec.new_rule()
      | clauses: [%{Spec.new_clause("has") | s: Spec.var(name), p: Spec.any(), o: Spec.any()}]
    }

    {:ok, ctx} = Builder.context([rule])
    Builder.to_rule(rule, ctx)
    assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
  end

  describe "values" do
    test "safe mode uses known pure functions and stands in for the rest" do
      rule = %{
        Spec.new_rule()
        | clauses: [
            %{Spec.new_clause("aggregate") | var: "m", over: "x", fun: "&min/1"},
            %{Spec.new_clause("filter_fn") | code: "fn -> File.rm_rf!(\"/\") end"}
          ]
      }

      [aggregate, %{filter: filter}] = Builder.to_rule(rule).forall

      assert aggregate.fun == (&Wongi.Engine.Aggregates.min/1)
      assert WongiEngineWebui.Expr.stand_in?(filter.func)
      assert filter.func.() == true
    end

    test "evaluate mode evaluates code with the DSL in scope" do
      rule = %{
        Spec.new_rule()
        | clauses: [%{Spec.new_clause("aggregate") | var: "m", over: "x", fun: "&max/1"}],
          actions: [%{Spec.new_action("code") | code: "fn t -> [{t[:m], :is, :max}] end"}]
      }

      {:ok, ctx} = Builder.context([rule], :evaluate)
      built = Builder.to_rule(rule, ctx)

      assert hd(built.forall).fun.([1, 3, 2]) == 3
      assert ctx.vars == %{"m" => :m, "x" => :x}
    end

    test "build errors carry the path of the field" do
      rule = %{
        Spec.new_rule()
        | actions: [%{Spec.new_action("code") | code: "fn t -> nope(t) end"}]
      }

      {:ok, ctx} = Builder.context([rule], :evaluate)

      error = assert_raise WongiEngineWebui.Builder.Error, fn -> Builder.to_rule(rule, ctx) end
      assert error.path == "actions.0.code"
      assert error.message =~ "undefined function nope/1"
    end
  end

  test "edges count the tokens passed along them" do
    {engine, _rules} = Example.engine()

    refs =
      Reconstruct.rules(engine)
      |> Enum.with_index()
      |> Enum.map(fn {{ref, _}, i} -> {i, ref, "r"} end)

    %{nodes: nodes, edges: edges} = Network.build(engine, refs)

    id = fn detail -> Enum.find(nodes, &(&1.detail == detail)).id end
    parent_x_y = id.("has(var(:x), :parent, var(:y))")
    parent_y_z = id.("has(var(:y), :parent, var(:z))")

    # alice -> bob and bob -> carol are parent facts; only alice has a grandparent
    assert Enum.find(edges, &(&1.source == parent_x_y and &1.target == parent_y_z)).count == 2
    assert Enum.all?(edges, &(&1.source != "n0" or &1.count == nil))
  end

  defp graph(rules, opts \\ []) do
    {engine, refs} =
      Enum.reduce(rules, {Wongi.Engine.new(), []}, fn rule, {engine, refs} ->
        {engine, ref} = Wongi.Engine.compile_and_get_ref(engine, rule)
        {engine, refs ++ [ref]}
      end)

    labels = refs |> Enum.with_index() |> Enum.map(fn {ref, i} -> {i, ref, "r#{i}"} end)
    Network.build(engine, labels, opts)
  end
end
