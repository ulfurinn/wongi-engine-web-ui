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
    assert graph(Enum.map(specs, &Builder.to_rule/1)) == graph(rules)
  end

  defp graph(rules) do
    {engine, refs} =
      Enum.reduce(rules, {Wongi.Engine.new(), []}, fn rule, {engine, refs} ->
        {engine, ref} = Wongi.Engine.compile_and_get_ref(engine, rule)
        {engine, refs ++ [ref]}
      end)

    labels = refs |> Enum.with_index() |> Enum.map(fn {ref, i} -> {i, ref, "r#{i}"} end)
    Network.build(engine, labels)
  end
end
