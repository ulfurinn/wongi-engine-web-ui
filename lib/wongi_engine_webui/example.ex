defmodule WongiEngineWebui.Example do
  @moduledoc """
  A small family-tree rule set, used by the standalone server and in tests.
  """

  use Wongi.Engine.DSL

  @doc "The example rules."
  def rules do
    [
      rule(:grandparent,
        forall: [
          has(var(:x), :parent, var(:y)),
          has(var(:y), :parent, var(:z))
        ],
        do: [gen(var(:x), :grandparent, var(:z))]
      ),
      rule(:orphan,
        forall: [
          has(var(:x), :is_a, :person),
          neg(var(:x), :parent, :_)
        ],
        do: [gen(var(:x), :orphan, true)]
      ),
      rule(:adult_without_children,
        forall: [
          has(var(:x), :is_a, :person),
          has(var(:x), :age, var(:age)),
          gte(var(:age), 18),
          ncc([has(var(:child), :parent, var(:x))])
        ],
        do: [gen(var(:x), :childless_adult, true)]
      ),
      rule(:youngest_grandchild,
        forall: [
          has(var(:x), :parent, var(:y)),
          has(var(:y), :parent, var(:z)),
          any([
            [has(var(:x), :age, var(:age))],
            [has(var(:x), :estimated_age, var(:age))]
          ]),
          aggregate(&min/1, :youngest, over: :age, partition: [:z])
        ],
        do: [gen(var(:z), :youngest_grandchild_age, var(:youngest))]
      )
    ]
  end

  @doc "Some facts for the example rules."
  def facts do
    [
      {:alice, :is_a, :person},
      {:alice, :age, 7},
      {:alice, :parent, :bob},
      {:bob, :is_a, :person},
      {:bob, :age, 35},
      {:bob, :parent, :carol},
      {:carol, :is_a, :person},
      {:carol, :age, 64},
      {:dave, :is_a, :person},
      {:dave, :age, 30}
    ]
  end

  @doc "An engine with the example rules and facts, plus the rules."
  def engine do
    rules = rules()
    engine = Enum.reduce(rules, Wongi.Engine.new(), &Wongi.Engine.compile(&2, &1))
    {Enum.reduce(facts(), engine, &Wongi.Engine.assert(&2, &1)), rules}
  end

  @doc """
  Whether the standalone editor evaluates code: only when
  `WONGI_ENGINE_WEBUI_EVALUATE` is set.
  """
  def evaluate?, do: System.get_env("WONGI_ENGINE_WEBUI_EVALUATE") in ~w(1 true)
end
