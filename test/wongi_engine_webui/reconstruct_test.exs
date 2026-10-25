defmodule WongiEngineWebui.ReconstructTest do
  use ExUnit.Case, async: true

  use Wongi.Engine.DSL

  alias WongiEngineWebui.Codegen
  alias WongiEngineWebui.Example
  alias WongiEngineWebui.Reconstruct

  test "rules recovered from the network match their definitions, except for names" do
    {engine, rules} = Example.engine()

    from_network = engine |> Reconstruct.rules() |> Enum.map(&Codegen.rule(elem(&1, 1)))
    from_rules = Enum.map(rules, &Codegen.rule(%{Reconstruct.from_rule(&1) | name: ""}))

    assert Enum.sort(from_network) == Enum.sort(from_rules)
  end

  test "given rules keep their names and order" do
    {engine, rules} = Example.engine()

    names = engine |> Reconstruct.rules(Enum.reverse(rules)) |> Enum.map(&elem(&1, 1).name)
    assert names == ~w(youngest_grandchild adult_without_children orphan grandparent)
  end

  test "functions are rendered as captures where possible" do
    rule =
      rule(
        forall: [has(var(:x), :age, var(:a)), filter(:a, &is_integer/1), filter(fn -> true end)],
        do: [gen(fn _token -> [] end)]
      )

    engine = Wongi.Engine.compile(Wongi.Engine.new(), rule)
    [{_ref, spec}] = Reconstruct.rules(engine)

    assert Codegen.rule(spec) =~ "filter(:a, &is_integer/1)"
    assert Codegen.rule(spec) =~ "filter(fn -> ... end)"
    assert Codegen.rule(spec) =~ "gen(fn _ -> ... end)"
  end
end
