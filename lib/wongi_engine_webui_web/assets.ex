defmodule WongiEngineWebuiWeb.Assets do
  @moduledoc """
  Serves the UI's JavaScript and CSS bundle from wherever the UI is mounted.

  The bundle is built into `priv/assets` by `mix assets.build` and
  embedded at compile time, so host applications need no asset pipeline of
  their own. Asset names carry a content hash, so they are cached forever,
  and a gzipped copy is served to clients that accept it.
  """

  @behaviour Plug

  import Plug.Conn

  @dir Path.expand("../../priv/assets/js", __DIR__)

  @assets (for {ext, content_type} <- [js: "text/javascript", css: "text/css"], into: %{} do
             path = Path.join(@dir, "app.#{ext}")
             @external_resource path
             content = if File.exists?(path), do: File.read!(path), else: ""

             hash =
               :crypto.hash(:md5, content) |> Base.encode16(case: :lower) |> binary_part(0, 12)

             {ext,
              %{
                name: "app-#{hash}.#{ext}",
                content: content,
                gzipped: :zlib.gzip(content),
                content_type: content_type
              }}
           end)

  @doc "The file name of the `:js` or `:css` asset, including its hash."
  def name(ext), do: @assets[ext].name

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{path_params: %{"asset" => name}} = conn, _opts) do
    case Enum.find(@assets, fn {_ext, asset} -> asset.name == name end) do
      {_ext, asset} ->
        conn
        # The host's :browser pipeline usually includes protect_from_forgery,
        # which rejects non-XHR JavaScript responses. This one is public.
        |> put_private(:plug_skip_csrf_protection, true)
        |> put_resp_content_type(asset.content_type)
        |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
        |> put_resp_header("vary", "accept-encoding")
        |> send_body(asset, accepts_gzip?(conn))
        |> halt()

      nil ->
        conn |> send_resp(404, "not found") |> halt()
    end
  end

  defp send_body(conn, asset, true) do
    conn
    |> put_resp_header("content-encoding", "gzip")
    |> send_resp(200, asset.gzipped)
  end

  defp send_body(conn, asset, false), do: send_resp(conn, 200, asset.content)

  defp accepts_gzip?(conn) do
    conn
    |> get_req_header("accept-encoding")
    |> Enum.any?(&String.contains?(&1, "gzip"))
  end
end
