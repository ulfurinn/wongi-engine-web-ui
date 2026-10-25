defmodule WongiEngineWebuiWeb.RuleComponents do
  @moduledoc """
  The structured rule editor.

  Inputs are named after spec paths (see `WongiEngineWebui.Spec`), so a
  single form covers a whole rule however deeply its clauses nest. Structural
  edits (adding, moving, removing) are `phx-click` events carrying a path.
  """
  use WongiEngineWebuiWeb, :html

  @clause_labels %{
    "has" => "has",
    "neg" => "neg",
    "filter" => "compare",
    "filter_fn" => "filter fn",
    "assign" => "assign",
    "ncc" => "none of",
    "any" => "any of",
    "aggregate" => "aggregate"
  }

  @clause_hints %{
    "has" => "matches a fact",
    "neg" => "no such fact",
    "filter" => "compares two values",
    "filter_fn" => "passes if the function returns true",
    "assign" => "binds a new variable",
    "ncc" => "the sub-chain doesn't match",
    "any" => "one of the branches matches",
    "aggregate" => "computes a value across tokens"
  }

  @filter_labels [
    {"equal", "equal"},
    {"diff", "diff"},
    {"less", "less"},
    {"lte", "lte"},
    {"greater", "greater"},
    {"gte", "gte"},
    {"in_list", "in_list"},
    {"not_in_list", "not_in_list"}
  ]

  @doc "The list of rules, as tabs."
  attr :rules, :list, required: true
  attr :selected, :integer, default: nil
  attr :invalid, :any, required: true, doc: "a set of indices of rules with errors"

  def rule_tabs(assigns) do
    ~H"""
    <nav id="rule-tabs" class="rule-tabs" aria-label="Rules">
      <button
        :for={{rule, index} <- Enum.with_index(@rules)}
        id={"rule-tab-#{rule.id}"}
        type="button"
        class={["rule-tab", index == @selected && "active"]}
        phx-click="select_rule"
        phx-value-index={index}
      >
        <span class="rule-tab-name">{rule_label(rule, index)}</span>
        <span :if={MapSet.member?(@invalid, index)} class="rule-tab-error" title="has errors">
          <.icon name="hero-exclamation-circle-mini" />
        </span>
      </button>
      <button id="add-rule" type="button" class="rule-tab rule-tab-add" phx-click="add_rule">
        <.icon name="hero-plus-mini" /> Rule
      </button>
    </nav>
    """
  end

  @doc "A rule's display name."
  def rule_label(%{name: ""}, index), do: "rule #{index + 1}"
  def rule_label(%{name: name}, _index), do: name

  @doc "The form for one rule."
  attr :form, :any, required: true
  attr :rule, :map, required: true
  attr :index, :integer, required: true
  attr :errors, :map, required: true
  attr :compile_error, :string, default: nil

  def rule_form(assigns) do
    ~H"""
    <.form for={@form} id="rule-form" class="rule-form" phx-change="change" phx-submit="change">
      <div class="rule-header">
        <.input
          field={@form["name"]}
          label="Rule name"
          placeholder="unnamed"
          autocomplete="off"
          errors={errors(@errors, "name")}
        />
        <button
          id="delete-rule"
          type="button"
          class="btn btn-ghost btn-danger"
          phx-click="delete_rule"
          phx-value-index={@index}
          data-confirm="Delete this rule?"
        >
          <.icon name="hero-trash" /> Delete
        </button>
      </div>

      <p :if={@compile_error} id="compile-error" class="compile-error">
        <.icon name="hero-exclamation-triangle" /> {@compile_error}
      </p>

      <section class="rule-section">
        <h2 class="section-title">
          Conditions <span class="section-dsl">forall:</span>
        </h2>
        <.clause_list
          form={@form}
          errors={@errors}
          clauses={@rule.clauses}
          path="clauses"
          types={WongiEngineWebui.Spec.clause_types()}
        />
      </section>

      <section class="rule-section">
        <h2 class="section-title">Actions <span class="section-dsl">do:</span></h2>
        <div class="item-list">
          <.action_item
            :for={{action, index} <- Enum.with_index(@rule.actions)}
            form={@form}
            errors={@errors}
            action={action}
            path={"actions.#{index}"}
          />
          <p :if={@rule.actions == []} class="empty-list">No actions.</p>
        </div>
        <div class="add-row">
          <button
            id="add-action-gen"
            type="button"
            class="chip"
            phx-click="add_action"
            phx-value-type="gen"
          >
            <.icon name="hero-plus-mini" /> gen
          </button>
          <button
            id="add-action-code"
            type="button"
            class="chip"
            phx-click="add_action"
            phx-value-type="code"
          >
            <.icon name="hero-plus-mini" /> function
          </button>
        </div>
      </section>
    </.form>
    """
  end

  attr :form, :any, required: true
  attr :errors, :map, required: true
  attr :clauses, :list, required: true
  attr :path, :string, required: true
  attr :types, :list, required: true

  defp clause_list(assigns) do
    ~H"""
    <div class="item-list">
      <.clause_item
        :for={{clause, index} <- Enum.with_index(@clauses)}
        form={@form}
        errors={@errors}
        clause={clause}
        path={"#{@path}.#{index}"}
      />
      <p :if={@clauses == []} class="empty-list">
        No clauses. <span :for={msg <- errors(@errors, @path)} class="inline-error">{msg}</span>
      </p>
    </div>
    <.add_menu path={@path} types={@types} />
    """
  end

  attr :path, :string, required: true
  attr :types, :list, required: true

  defp add_menu(assigns) do
    assigns = assign(assigns, labels: @clause_labels, hints: @clause_hints)

    ~H"""
    <details class="add-menu" id={dom_id("add-menu", @path)}>
      <summary class="chip"><.icon name="hero-plus-mini" /> clause</summary>
      <div class="add-menu-items">
        <button
          :for={type <- @types}
          type="button"
          class="add-menu-item"
          phx-click="add_clause"
          phx-value-path={@path}
          phx-value-type={type}
        >
          <span class={["type-dot", "type-#{type}"]} />
          <span class="add-menu-label">{@labels[type]}</span>
          <span class="add-menu-hint">{@hints[type]}</span>
        </button>
      </div>
    </details>
    """
  end

  attr :form, :any, required: true
  attr :errors, :map, required: true
  attr :clause, :map, required: true
  attr :path, :string, required: true

  defp clause_item(assigns) do
    assigns = assign(assigns, :label, @clause_labels[assigns.clause.type])

    ~H"""
    <div class={["item", "item-#{@clause.type}"]} id={dom_id("item", @path)}>
      <.item_header path={@path} label={@label} type={@clause.type} />
      <div class="item-body">
        <.clause_fields form={@form} errors={@errors} clause={@clause} path={@path} />
      </div>
    </div>
    """
  end

  attr :path, :string, required: true
  attr :label, :string, required: true
  attr :type, :string, required: true

  defp item_header(assigns) do
    ~H"""
    <div class="item-header">
      <span class={["type-dot", "type-#{@type}"]} />
      <span class="item-label">{@label}</span>
      <span class="item-controls">
        <button
          type="button"
          class="icon-btn"
          title="Move up"
          phx-click="move"
          phx-value-path={@path}
          phx-value-offset="-1"
        >
          <.icon name="hero-chevron-up-mini" />
        </button>
        <button
          type="button"
          class="icon-btn"
          title="Move down"
          phx-click="move"
          phx-value-path={@path}
          phx-value-offset="1"
        >
          <.icon name="hero-chevron-down-mini" />
        </button>
        <button
          type="button"
          class="icon-btn icon-btn-danger"
          title="Remove"
          phx-click="remove"
          phx-value-path={@path}
        >
          <.icon name="hero-x-mark-mini" />
        </button>
      </span>
    </div>
    """
  end

  attr :form, :any, required: true
  attr :errors, :map, required: true
  attr :clause, :map, required: true
  attr :path, :string, required: true

  defp clause_fields(%{clause: %{type: type}} = assigns) when type in ~w(has neg) do
    ~H"""
    <div class="triple">
      <.term form={@form} errors={@errors} path={@path <> ".s"} label="subject" />
      <.term form={@form} errors={@errors} path={@path <> ".p"} label="predicate" />
      <.term form={@form} errors={@errors} path={@path <> ".o"} label="object" />
    </div>
    <div :if={@clause.type == "has" and Map.get(@clause, :when, []) != []} class="nested">
      <span class="nested-label">when</span>
      <.clause_list
        form={@form}
        errors={@errors}
        clauses={@clause.when}
        path={@path <> ".when"}
        types={~w(filter filter_fn)}
      />
    </div>
    """
  end

  defp clause_fields(%{clause: %{type: "ncc"}} = assigns) do
    ~H"""
    <div class="nested">
      <.clause_list
        form={@form}
        errors={@errors}
        clauses={@clause.clauses}
        path={@path <> ".clauses"}
        types={WongiEngineWebui.Spec.clause_types()}
      />
    </div>
    """
  end

  defp clause_fields(%{clause: %{type: "any"}} = assigns) do
    ~H"""
    <div :for={{branch, index} <- Enum.with_index(@clause.branches)} class="nested branch">
      <div class="branch-header">
        <span class="nested-label">branch {index + 1}</span>
        <button
          type="button"
          class="icon-btn icon-btn-danger"
          title="Remove branch"
          phx-click="remove"
          phx-value-path={"#{@path}.branches.#{index}"}
        >
          <.icon name="hero-x-mark-mini" />
        </button>
      </div>
      <.clause_list
        form={@form}
        errors={@errors}
        clauses={branch.clauses}
        path={"#{@path}.branches.#{index}.clauses"}
        types={WongiEngineWebui.Spec.clause_types()}
      />
    </div>
    <span :for={msg <- errors(@errors, @path)} class="inline-error">{msg}</span>
    <button type="button" class="chip" phx-click="add_branch" phx-value-path={@path}>
      <.icon name="hero-plus-mini" /> branch
    </button>
    """
  end

  defp clause_fields(%{clause: %{type: "filter"}} = assigns) do
    assigns = assign(assigns, :ops, @filter_labels)

    ~H"""
    <.input
      type="select"
      field={@form[@path <> ".op"]}
      options={@ops}
      class="op-select"
      aria-label="comparison"
      errors={errors(@errors, @path <> ".op")}
    />
    <div class="pair">
      <.term form={@form} errors={@errors} path={@path <> ".a"} label="left" />
      <.term form={@form} errors={@errors} path={@path <> ".b"} label="right" />
    </div>
    """
  end

  defp clause_fields(%{clause: %{type: "filter_fn"}} = assigns) do
    ~H"""
    <.name_input form={@form} errors={@errors} path={@path <> ".var"} label="variable (optional)" />
    <.code_input form={@form} errors={@errors} path={@path <> ".code"} />
    """
  end

  defp clause_fields(%{clause: %{type: "assign"}} = assigns) do
    ~H"""
    <div class="pair">
      <.name_input form={@form} errors={@errors} path={@path <> ".name"} label="variable" />
      <.code_input
        form={@form}
        errors={@errors}
        path={@path <> ".value"}
        label="value"
        rows={1}
        placeholder="a value, or fn token -> ... end"
      />
    </div>
    """
  end

  defp clause_fields(%{clause: %{type: "aggregate"}} = assigns) do
    ~H"""
    <div class="pair">
      <.code_input
        form={@form}
        errors={@errors}
        path={@path <> ".fun"}
        label="function"
        rows={1}
        placeholder="&min/1"
      />
      <.name_input form={@form} errors={@errors} path={@path <> ".var"} label="result" />
    </div>
    <div class="pair">
      <.name_input form={@form} errors={@errors} path={@path <> ".over"} label="over" />
      <.code_input
        form={@form}
        errors={@errors}
        path={@path <> ".map"}
        label="or map"
        rows={1}
        placeholder="fn token -> ... end"
      />
    </div>
    <.name_input
      form={@form}
      errors={@errors}
      path={@path <> ".partition"}
      label="partition by"
      placeholder="var, var"
    />
    """
  end

  attr :form, :any, required: true
  attr :errors, :map, required: true
  attr :action, :map, required: true
  attr :path, :string, required: true

  defp action_item(assigns) do
    ~H"""
    <div class={["item", "item-action"]} id={dom_id("item", @path)}>
      <.item_header
        path={@path}
        label={if @action.type == "gen", do: "gen", else: "function"}
        type="action"
      />
      <div class="item-body">
        <div :if={@action.type == "gen"} class="triple">
          <.term form={@form} errors={@errors} path={@path <> ".s"} label="subject" />
          <.term form={@form} errors={@errors} path={@path <> ".p"} label="predicate" />
          <.term form={@form} errors={@errors} path={@path <> ".o"} label="object" />
        </div>
        <.code_input
          :if={@action.type == "code"}
          form={@form}
          errors={@errors}
          path={@path <> ".code"}
        />
      </div>
    </div>
    """
  end

  attr :form, :any, required: true
  attr :errors, :map, required: true
  attr :path, :string, required: true
  attr :label, :string, required: true

  defp term(assigns) do
    assigns = assign(assigns, :kind, assigns.form[assigns.path <> ".kind"].value)

    ~H"""
    <div class={["term", "term-#{@kind}"]}>
      <div class="term-head">
        <span class="term-label">{@label}</span>
        <.input
          type="select"
          field={@form[@path <> ".kind"]}
          options={[{"var", "var"}, {"any", "any"}, {"value", "expr"}]}
          class="term-kind"
          aria-label={"#{@label} kind"}
        />
      </div>
      <span :if={@kind == "any"} class="term-placeholder">:_</span>
      <.input
        :if={@kind != "any"}
        type="text"
        field={@form[@path <> ".value"]}
        class={["term-value", @kind == "expr" && "code"]}
        placeholder={if @kind == "var", do: "name", else: ":atom, 42, \"text\""}
        autocomplete="off"
        spellcheck="false"
        phx-debounce="300"
        aria-label={"#{@label} value"}
        errors={errors(@errors, @path <> ".value")}
      />
    </div>
    """
  end

  attr :form, :any, required: true
  attr :errors, :map, required: true
  attr :path, :string, required: true
  attr :label, :string, required: true
  attr :placeholder, :string, default: "name"

  defp name_input(assigns) do
    ~H"""
    <.input
      type="text"
      field={@form[@path]}
      label={@label}
      placeholder={@placeholder}
      autocomplete="off"
      spellcheck="false"
      phx-debounce="300"
      errors={errors(@errors, @path)}
    />
    """
  end

  attr :form, :any, required: true
  attr :errors, :map, required: true
  attr :path, :string, required: true
  attr :label, :string, default: "code"
  attr :rows, :integer, default: 2
  attr :placeholder, :string, default: nil

  defp code_input(assigns) do
    ~H"""
    <.input
      type="textarea"
      field={@form[@path]}
      label={@label}
      rows={@rows}
      class="code"
      placeholder={@placeholder}
      spellcheck="false"
      phx-debounce="300"
      errors={errors(@errors, @path)}
    />
    """
  end

  # Paths contain dots, which would need escaping in CSS selectors.
  defp dom_id(prefix, path), do: prefix <> "-" <> String.replace(path, ".", "-")

  defp errors(errors, path) do
    case Map.fetch(errors, path) do
      {:ok, message} -> [message]
      :error -> []
    end
  end
end
