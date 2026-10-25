defmodule WongiEngineWebuiWeb.PageController do
  use WongiEngineWebuiWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
