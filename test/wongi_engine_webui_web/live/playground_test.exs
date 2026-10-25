defmodule WongiEngineWebuiWeb.PlaygroundTest do
  use WongiEngineWebuiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias WongiEngineWebuiWeb.EngineLive

  describe "facts" do
    test "the example facts propagate", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      view |> element("#tab-facts") |> render_click()

      assert has_element?(view, "#facts-form #fact-9")
      assert has_element?(view, "#inferred-facts .fact", ":grandparent")
      assert has_element?(view, "#code-facts")

      assert_push_event(view, "graph", %{edges: edges, nodes: nodes})
      assert Enum.any?(edges, &((&1.count || 0) > 0))
      assert Enum.any?(nodes, &(&1.type == "production" and &1.tokens > 0))
    end

    test "facts can be added, edited and removed", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      view |> element("#tab-facts") |> render_click()
      view |> element("#clear-facts") |> render_click()
      refute has_element?(view, "#inferred-facts")

      view |> element("#add-fact") |> render_click()
      view |> element("#add-fact") |> render_click()

      view
      |> form("#facts-form")
      |> render_change(%{
        "facts" => %{
          "facts.0.s" => ":a",
          "facts.0.p" => ":parent",
          "facts.0.o" => ":b",
          "facts.1.s" => ":b",
          "facts.1.p" => ":parent",
          "facts.1.o" => ":c"
        }
      })

      assert has_element?(view, "#inferred-facts .fact", ":grandparent")

      view |> element("#fact-1 button") |> render_click()
      refute has_element?(view, "#inferred-facts")
    end

    test "safe mode only accepts literal facts", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      view |> element("#tab-facts") |> render_click()

      view
      |> form("#facts-form")
      |> render_change(%{"facts" => %{"facts.0.o" => "System.halt()"}})

      assert has_element?(view, "#fact-0 .field-error", "must be a literal value")
    end

    test "facts can be imported", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      view |> element("#tab-facts") |> render_click()
      view |> element("#clear-facts") |> render_click()

      view
      |> form("#import-form", import: %{text: "{:x, :parent, :y}\n{:y, :parent, :z}"})
      |> render_submit()

      assert has_element?(view, "#fact-1")
      assert has_element?(view, "#inferred-facts .fact", ":z")
    end
  end

  describe "code evaluation" do
    setup do
      rule = %{
        WongiEngineWebui.Spec.new_rule("adult")
        | clauses: [
            %{
              WongiEngineWebui.Spec.new_clause("has")
              | s: WongiEngineWebui.Spec.var("x"),
                p: WongiEngineWebui.Spec.expr(":age"),
                o: WongiEngineWebui.Spec.var("age")
            },
            %{
              WongiEngineWebui.Spec.new_clause("filter_fn")
              | var: "age",
                code: "fn age -> age >= 18 end"
            }
          ],
          actions: [
            %{
              WongiEngineWebui.Spec.new_action("code")
              | code: "fn token -> [{token[:x], :adult, true}] end"
            }
          ]
      }

      %{rule: rule}
    end

    test "is off by default: functions are stand-ins", %{conn: conn, rule: rule} do
      {:ok, view, _html} = live_isolated(conn, EngineLive, session: session(rule, false))

      assert has_element?(view, "#evaluation-mode", "safe mode")
      assert_push_event(view, "graph", %{nodes: nodes})
      assert Enum.any?(nodes, & &1.stand_in)

      # the stand-in filter passes everything; the stand-in action does nothing
      view |> element("#tab-facts") |> render_click()
      refute has_element?(view, "#inferred-facts")
    end

    test "can be enabled", %{conn: conn, rule: rule} do
      {:ok, view, _html} = live_isolated(conn, EngineLive, session: session(rule, true))

      assert has_element?(view, "#evaluation-mode", "evaluating code")
      assert_push_event(view, "graph", %{nodes: nodes})
      refute Enum.any?(nodes, & &1.stand_in)

      view |> element("#tab-facts") |> render_click()
      assert has_element?(view, "#inferred-facts .fact", ":bob")
      refute has_element?(view, "#inferred-facts .fact", ":alice")
    end

    test "reports errors raised by the code", %{conn: conn, rule: rule} do
      rule =
        put_in(
          rule.clauses,
          Enum.take(rule.clauses, 1) ++
            [%{WongiEngineWebui.Spec.new_clause("filter_fn") | code: "fn -> undefined_fun() end"}]
        )

      {:ok, view, _html} = live_isolated(conn, EngineLive, session: session(rule, true))

      assert has_element?(view, "#rule-form .field-error", "undefined function undefined_fun/0")
    end

    defp session(rule, evaluate) do
      %{
        "initial_rules" => {List, :wrap, [rule]},
        "initial_facts" => {List, :wrap, [[{:alice, :age, 7}, {:bob, :age, 35}]]},
        "evaluate" => evaluate
      }
    end
  end
end
