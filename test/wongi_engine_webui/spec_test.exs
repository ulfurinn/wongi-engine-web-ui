defmodule WongiEngineWebui.SpecTest do
  use ExUnit.Case, async: true

  alias WongiEngineWebui.Spec

  setup do
    rule =
      Spec.new_rule("r")
      |> Spec.append("clauses", Spec.new_clause("has"))
      |> Spec.append("clauses", Spec.new_clause("any"))
      |> Spec.append("clauses.1.branches.0.clauses", Spec.new_clause("neg"))

    %{rule: rule}
  end

  test "flatten/1 and apply_params/2 round-trip", %{rule: rule} do
    flat = Spec.flatten(rule)
    assert flat["clauses.1.branches.0.clauses.0.type"] == "neg"

    edited = Spec.apply_params(rule, %{flat | "clauses.0.s.value" => "x"})
    assert Spec.get(edited, "clauses.0.s.value") == "x"
    assert Spec.flatten(edited) == %{flat | "clauses.0.s.value" => "x"}
  end

  test "apply_params/2 ignores unknown paths and non-leaves", %{rule: rule} do
    params = %{"clauses.9.s.value" => "x", "nonsense" => "x", "clauses.0" => "x"}
    assert Spec.apply_params(rule, params) == rule
  end

  test "move/3 and remove/2 address list elements", %{rule: rule} do
    moved = Spec.move(rule, "clauses.1", -1)
    assert Enum.map(moved.clauses, & &1.type) == ["any", "has"]
    assert Spec.move(rule, "clauses.1", 1) == rule

    removed = Spec.remove(rule, "clauses.1.branches.0.clauses.0")
    assert Spec.get(removed, "clauses.1.branches.0.clauses") == []
  end
end
