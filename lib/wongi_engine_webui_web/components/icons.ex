defmodule WongiEngineWebuiWeb.Icons do
  @moduledoc """
  Embeds the [Heroicons](https://heroicons.com) SVGs from `deps/heroicons`
  at compile time so they can be rendered inline by `CoreComponents.icon/1`.

  Icon names follow the `hero-<name>[-solid|-mini|-micro]` convention.
  """

  @root Path.expand("../../../deps/heroicons/optimized", __DIR__)

  @variants [
    {"", "24/outline"},
    {"-solid", "24/solid"},
    {"-mini", "20/solid"},
    {"-micro", "16/solid"}
  ]

  @external_resource @root

  @icons (for {suffix, dir} <- @variants,
              path <- Path.wildcard(Path.join([@root, dir, "*.svg"])),
              into: %{} do
            svg = File.read!(path)
            [_, attrs, inner] = Regex.run(~r{<svg([^>]*)>(.*)</svg>}s, svg)

            attrs =
              for [_, key, value] <- Regex.scan(~r{([\w-]+)="([^"]*)"}, attrs),
                  key not in ~w(xmlns data-slot),
                  do: {key, value}

            {"hero-" <> Path.basename(path, ".svg") <> suffix, {attrs, String.trim(inner)}}
          end)

  if map_size(@icons) == 0 do
    raise "no heroicons found in #{@root}, run `mix deps.get`"
  end

  @doc """
  Returns `{svg_attributes, inner_svg_markup}` for the given icon name.
  """
  def fetch!(name) do
    case Map.fetch(@icons, name) do
      {:ok, icon} -> icon
      :error -> raise ArgumentError, "unknown icon #{inspect(name)}"
    end
  end
end
