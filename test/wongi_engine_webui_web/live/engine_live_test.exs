defmodule WongiEngineWebuiWeb.EngineLiveTest do
  use WongiEngineWebuiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "editor" do
    test "starts with the configured rules", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      assert has_element?(view, "#rule-form")
      assert has_element?(view, "#rete-graph")
      assert has_element?(view, "#code-rule-3")
      assert_push_event(view, "graph", %{nodes: [%{type: "root"} | _]})
    end

    test "adding a clause recompiles the network", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      assert_push_event(view, "graph", %{nodes: nodes})

      view
      |> element("#add-menu-clauses button[phx-value-type=has]")
      |> render_click()

      # the new clause is blank, so the rule is invalid and drops out
      assert has_element?(view, "#rule-tab-#{first_rule_id(view)} .rule-tab-error")
      assert_push_event(view, "graph", %{nodes: fewer})
      assert length(fewer) < length(nodes)

      view
      |> form("#rule-form")
      |> render_change(%{
        "rule" => %{
          "clauses.2.s.value" => "z",
          "clauses.2.p.value" => ":age",
          "clauses.2.o.value" => "age"
        }
      })

      refute has_element?(view, ".rule-tab-error")
      assert_push_event(view, "graph", %{nodes: more})
      assert length(more) == length(nodes) + 1
    end

    test "shows parse errors inline", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      view
      |> form("#rule-form")
      |> render_change(%{"rule" => %{"clauses.0.p.value" => ":parent("}})

      assert has_element?(view, "#rule-form .field-error", "missing terminator")
      assert has_element?(view, "#code-rule-0.invalid")
    end

    test "rules can be added, selected and deleted", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      view |> element("#add-rule") |> render_click()
      assert has_element?(view, "#code-rule-4.active")

      view |> element("#delete-rule") |> render_click()
      refute has_element?(view, "#code-rule-4")

      view |> element("#code-rule-1") |> render_click()
      assert has_element?(view, "#code-rule-1.active")
      assert_push_event(view, "select", %{rule: 1})
    end
  end

  describe "read-only" do
    test "shows the engine without an editor", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/example")

      refute has_element?(view, "#rule-form")
      assert has_element?(view, "#reload-engine")
      assert has_element?(view, "#code-rule-0", "grandparent")
      assert_push_event(view, "graph", %{nodes: nodes})
      assert Enum.any?(nodes, &(&1.tokens > 0))
    end

    test "selecting a node shows its details", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/example")
      assert_push_event(view, "graph", %{nodes: [_root, join | _]})

      render_hook(view, "select_node", %{"id" => join.id})

      assert has_element?(view, "#node-details", "has")
      join_id = join.id
      assert_push_event(view, "select", %{node: ^join_id})
    end

    test "ignores editing events", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/example")
      render_hook(view, "add_rule", %{})
      refute has_element?(view, "#code-rule-4")
    end
  end

  test "serves the asset bundle", %{conn: conn} do
    name = WongiEngineWebuiWeb.Assets.name(:js)

    # ConnTest skips CSRF protection, which is what would reject the script
    conn =
      conn
      |> put_private(:plug_skip_csrf_protection, false)
      |> put_req_header("accept-encoding", "gzip")
      |> get("/example/_assets/#{name}")

    assert response(conn, 200)
    assert get_resp_header(conn, "content-type") == ["text/javascript; charset=utf-8"]
    assert get_resp_header(conn, "content-encoding") == ["gzip"]

    assert build_conn() |> get("/example/_assets/app-nope.js") |> response(404)
  end

  defp first_rule_id(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(".rule-tab")
    |> LazyHTML.attribute("id")
    |> hd()
    |> String.replace_prefix("rule-tab-", "")
  end
end
