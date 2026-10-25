defmodule WongiEngineWebuiWeb.PageControllerTest do
  use WongiEngineWebuiWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Wongi Engine"
  end
end
