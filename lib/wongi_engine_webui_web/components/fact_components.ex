defmodule WongiEngineWebuiWeb.FactComponents do
  @moduledoc """
  The facts panel: facts asserted into the playground, and the facts the rules
  inferred from them.
  """
  use WongiEngineWebuiWeb, :html

  alias WongiEngineWebui.Spec
  alias WongiEngineWebui.Value

  @doc "The facts panel."
  attr :editable, :boolean, required: true
  attr :form, :any, default: nil
  attr :facts, :list, default: [], doc: "fact specs, when editable"
  attr :errors, :map, default: %{}
  attr :facts_error, :any, default: nil
  attr :asserted, :list, required: true, doc: "asserted facts as source triples"
  attr :inferred, :list, required: true, doc: "inferred facts as source triples"

  def facts_panel(assigns) do
    ~H"""
    <div id="facts-panel" class="facts-panel">
      <section class="rule-section">
        <header class="facts-header">
          <h2 class="section-title">
            Asserted
            <span class="section-dsl">{if @editable, do: length(@facts), else: length(@asserted)}</span>
          </h2>
          <button
            :if={@editable and @facts != []}
            id="clear-facts"
            type="button"
            class="btn btn-ghost btn-small btn-danger"
            phx-click="clear_facts"
            data-confirm="Remove all facts?"
          >
            Clear
          </button>
        </header>

        <p :if={@facts_error} id="facts-error" class="compile-error">
          <.icon name="hero-exclamation-triangle" /> {@facts_error}
        </p>

        <.form
          :if={@editable}
          for={@form}
          id="facts-form"
          class="fact-rows"
          phx-change="change_facts"
          phx-submit="change_facts"
        >
          <div :for={{_fact, index} <- Enum.with_index(@facts)} class="fact-row" id={"fact-#{index}"}>
            <.input
              :for={field <- ~w(s p o)}
              type="text"
              field={@form["facts.#{index}.#{field}"]}
              class="code"
              placeholder={placeholder(field)}
              autocomplete="off"
              spellcheck="false"
              phx-debounce="300"
              aria-label={"fact #{index + 1} #{placeholder(field)}"}
              errors={errors(@errors, "facts.#{index}.#{field}")}
            />
            <button
              type="button"
              class="icon-btn icon-btn-danger"
              title="Remove fact"
              phx-click="remove_fact"
              phx-value-index={index}
            >
              <.icon name="hero-x-mark-mini" />
            </button>
          </div>
        </.form>

        <p :if={@editable and @facts == []} class="empty-list">
          No facts. Add some to see how they propagate through the network.
        </p>

        <div :if={@editable} class="add-row">
          <button id="add-fact" type="button" class="chip" phx-click="add_fact">
            <.icon name="hero-plus-mini" /> fact
          </button>
          <details class="import" id="import-facts">
            <summary class="chip"><.icon name="hero-arrow-down-tray-mini" /> import</summary>
            <.form
              for={to_form(%{"text" => ""}, as: :import)}
              id="import-form"
              class="import-form"
              phx-submit="import_facts"
            >
              <.input
                type="textarea"
                name="import[text]"
                value=""
                rows={5}
                class="code"
                placeholder="{:alice, :parent, :bob}\n{:bob, :age, 35}"
                spellcheck="false"
              />
              <p class="import-hint">One tuple per line, or a list of tuples.</p>
              <button type="submit" class="btn btn-small">Add facts</button>
            </.form>
          </details>
        </div>

        <.fact_list :if={not @editable} id="asserted-facts" facts={@asserted} />
      </section>

      <section class="rule-section">
        <h2 class="section-title">
          Inferred <span class="section-dsl">{length(@inferred)}</span>
        </h2>
        <.fact_list id="inferred-facts" facts={@inferred} />
        <p :if={@inferred == []} class="empty-list">
          Nothing yet. Facts produced by <code>gen</code> actions appear here.
        </p>
      </section>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :facts, :list, required: true

  defp fact_list(assigns) do
    ~H"""
    <ul :if={@facts != []} id={@id} class="fact-list">
      <li :for={{s, p, o} <- @facts} class="fact">
        <span class="fact-part">{s}</span>
        <span class="fact-part">{p}</span>
        <span class="fact-part">{o}</span>
      </li>
    </ul>
    """
  end

  defp placeholder("s"), do: "subject"
  defp placeholder("p"), do: "predicate"
  defp placeholder("o"), do: "object"

  defp errors(errors, path) do
    case Map.fetch(errors, path) do
      {:ok, message} -> [message]
      :error -> []
    end
  end

  @doc """
  Parses pasted facts: a list of 3-tuples, or one 3-tuple per line. Only
  literal values are accepted.
  """
  @spec parse_import(String.t()) :: {:ok, [map()]} | {:error, String.t()}
  def parse_import(text) do
    text = String.trim(text)

    source =
      if String.starts_with?(text, "[") do
        text
      else
        lines = text |> String.split("\n") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
        "[" <> Enum.join(lines, ",\n") <> "]"
      end

    case Value.read(source) do
      {:ok, items} when is_list(items) ->
        if Enum.all?(items, &(is_tuple(&1) and tuple_size(&1) == 3)) do
          {:ok,
           for {s, p, o} <- items do
             Spec.new_fact(Value.to_source(s), Value.to_source(p), Value.to_source(o))
           end}
        else
          {:error, "expected {subject, predicate, object} tuples"}
        end

      {:error, message} ->
        {:error, "couldn't read the facts: " <> message}

      _ ->
        {:error, "facts must be literal values, such as {:alice, :age, 7}"}
    end
  end
end
