defmodule WongiEngineWebui.CodegenTest do
  use ExUnit.Case, async: true

  alias WongiEngineWebui.Codegen
  alias WongiEngineWebui.Spec

  test "renders a rule" do
    rule = %{
      Spec.new_rule("adult")
      | clauses: [
          %{Spec.new_clause("has") | s: Spec.var("x"), p: Spec.expr(":age"), o: Spec.var("age")},
          %{Spec.new_clause("filter") | op: "gte", a: Spec.var("age"), b: Spec.expr("18")},
          %{Spec.new_clause("neg") | s: Spec.var("x"), p: Spec.expr(":dead"), o: Spec.any()}
        ],
        actions: [
          %{
            Spec.new_action("gen")
            | s: Spec.var("x"),
              p: Spec.expr(":adult"),
              o: Spec.expr("true")
          }
        ]
    }

    assert Codegen.rule(rule) == """
           rule(:adult,
             forall: [
               has(var(:x), :age, var(:age)),
               gte(var(:age), 18),
               neg(var(:x), :dead, :_)
             ],
             do: [gen(var(:x), :adult, true)]
           )\
           """
  end

  test "quotes names that aren't plain identifiers" do
    assert Codegen.atom("my rule") == ~s(:"my rule")
  end

  test "keeps source that doesn't parse unformatted" do
    rule = %{Spec.new_rule() | actions: [%{Spec.new_action("code") | code: "fn ->"}]}
    assert Codegen.rule(rule) == "rule(forall: [], do: [fn ->])"
  end
end
