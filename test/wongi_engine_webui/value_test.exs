defmodule WongiEngineWebui.ValueTest do
  use ExUnit.Case, async: true

  alias WongiEngineWebui.Value
  alias WongiEngineWebui.Value.Atom

  test "reads literals without creating atoms" do
    name = "never_seen_#{System.unique_integer([:positive])}"

    assert Value.read(":#{name}") == {:ok, %Atom{name: name}}

    assert Value.read(~s([1, -2.5, "s", nil, {true, %{k: :v}}])) ==
             {:ok, [1, -2.5, "s", nil, {true, %{%Atom{name: "k"} => %Atom{name: "v"}}}]}

    assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
  end

  test "reads real atoms on request" do
    assert Value.read(":ok", atoms: :real) == {:ok, :ok}
  end

  test "rejects code that isn't a literal" do
    assert Value.read("fn -> 1 end") == :not_literal
    assert Value.read("File.rm!(\"x\")") == :not_literal
    assert {:error, _} = Value.read("{")
  end

  test "to_source/1 round-trips literals" do
    for source <- [~s({:a, "b", [1, 2.5]}), ":\"with space\"", "%{1 => :x}"] do
      {:ok, value} = Value.read(source)
      assert Value.read(Value.to_source(value)) == {:ok, value}
    end
  end
end
