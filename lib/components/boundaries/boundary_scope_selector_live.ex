defmodule Bonfire.UI.Groups.BoundaryScopeSelectorLive do
  use Bonfire.UI.Common.Web, :stateless_component

  @doc "Dimension atom: :visibility or :default_content_visibility"
  prop dimension, :atom, required: true

  @doc "Label for the dimension shown as a heading"
  prop label, :string, required: true

  @doc "Optional description shown below the label"
  prop description, :string, default: nil

  @doc "Ordered list of all slugs (from preset_dimensions config)"
  prop slug_order, :list, default: []

  @doc "Map of slug => option metadata (label, description, disabled, icon, role)"
  prop options, :map, default: %{}

  @doc "Currently selected slug (e.g. 'local:discoverable')"
  prop selected, :string, default: nil

  @doc "HTML form field name for the hidden input"
  prop name, :string, required: true

  @doc "phx-target for click events"
  prop target, :any, default: nil

  @doc "List of scopes to disable (derived from DCV cascading)"
  prop disabled_scopes, :list, default: []

  @doc "Optional list of user's circles to show as selectable options"
  prop circles, :list, default: []

  @doc "When true, disabled/coming-soon options are shown grayed out. When false (default), they are hidden."
  prop show_unavailable, :boolean, default: false

  def render(assigns) do
    selected = assigns[:selected]
    selected_scope = if selected, do: slug_to_scope(selected)
    scopes_cfg = Bonfire.Common.Config.get(:scopes, %{}, :bonfire_boundaries)
    role_verbs_cfg = Bonfire.Common.Config.get(:role_verbs, %{})
    slug_order = assigns[:slug_order] || []
    options = assigns[:options] || %{}

    scope_order =
      slug_order
      |> Enum.map(&slug_to_scope/1)
      |> Enum.uniq()

    scope_ordered =
      Enum.map(scope_order, fn scope ->
        {scope, ed(scopes_cfg, scope, %{}), selected_scope == scope}
      end)

    scope_slugs =
      slug_order
      |> Enum.filter(&(slug_to_scope(&1) == selected_scope))
      |> Enum.map(fn slug ->
        opt = ed(options, slug, %{})
        access_role = e(opt, :role, :interact)
        {slug, opt, ed(role_verbs_cfg, access_role, %{}), access_role, selected == slug}
      end)

    assigns
    |> assign(
      selected_scope: selected_scope,
      selected_access: if(selected, do: ed(options, selected, :role, :interact)),
      scope_ordered: scope_ordered,
      scope_slugs: scope_slugs
      # access_roles: [:interact, :discover, :unlisted_read]
    )
    |> render_sface()
  end

  @doc "Extracts the scope portion from a combined slug (e.g. 'local:discoverable' → 'local', 'members:private' → 'members'). Bare slugs that aren't known scopes default to 'global'."
  def slug_to_scope(slug) when is_binary(slug) do
    known_scopes =
      Map.keys(Bonfire.Common.Config.get(:scopes, %{}, :bonfire_boundaries))
      |> Enum.map(&to_string/1)

    scope =
      case String.split(slug, ":", parts: 2) do
        [scope, _] -> scope
        [scope] -> scope
      end

    if scope in known_scopes, do: scope, else: "global"
  end

  def slug_to_scope(_), do: nil
end
