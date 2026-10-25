defmodule WongiEngineWebui.ExprTest do
  use ExUnit.Case, async: true

  alias WongiEngineWebui.Expr

  describe "parse/1" do
    test "parses valid expressions" do
      assert {:ok, _} = Expr.parse(":is_a")
      assert {:ok, _} = Expr.parse("fn x -> x > 1 end")
    end

    test "reports syntax errors and blanks" do
      assert {:error, "missing terminator: )" <> _} = Expr.parse("foo(")
      assert {:error, "can't be blank"} = Expr.parse("  ")
    end

    test "does not create atoms" do
      name = "never_seen_#{System.unique_integer([:positive])}"
      assert {:ok, _} = Expr.parse(":#{name}")
      assert {:ok, _} = Expr.parse("fn #{name} -> #{name} end")
      assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
    end
  end

  test "fn_arity/1 recognises function literals" do
    arity = fn source -> source |> Expr.parse() |> elem(1) |> Expr.fn_arity() end

    assert arity.("fn -> true end") == 0
    assert arity.("fn a, b -> a end") == 2
    assert arity.("fn a when is_integer(a) -> a end") == 1
    assert arity.("&min/1") == 1
    assert arity.("&(&1 + &2)") == 2
    assert arity.(":not_a_function") == nil
  end

  describe "stand_in/2" do
    test "functions become placeholders that remember their source" do
      fun = Expr.stand_in("fn x -> x end", true)
      assert is_function(fun, 1)
      assert fun.(:anything) == true
      assert Expr.source(fun) == {:ok, "fn x -> x end"}
    end

    test "placeholders are equal exactly when their sources are" do
      assert Expr.stand_in("fn x -> x end") == Expr.stand_in("fn x -> x end")
      refute Expr.stand_in("fn x -> x end") == Expr.stand_in("fn y -> y end")
    end

    test "other expressions become constants" do
      assert Expr.stand_in(" :foo ") == %Expr{source: ":foo"}
    end
  end
end
