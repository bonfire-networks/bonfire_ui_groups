defmodule Bonfire.UI.Groups.GroupBoundaryEditorLive do
  @moduledoc """
  Reusable three-layer permission editor for groups.

  Layer 1: audience presets.
  Layer 2: aggregated toggles (discoverable / federate / approval / anyone posts).
  Layer 3: per-dimension matrix, collapsed behind Advanced.

  Embedded by the new-group modal (`NewGroupFormLive`) and the group settings
  boundaries tab (`Settings.BoundariesLive`). The host form owns name/description
  and submit; this component only renders the boundary controls and the hidden
  inputs that mirror the chosen dimension slugs into the surrounding form.
  """

  use Bonfire.UI.Common.Web, :stateful_component

  prop initial_preset, :any, default: nil
  prop initial_membership, :any, default: nil
  prop initial_visibility, :any, default: nil
  prop initial_participation, :any, default: nil
  prop initial_default_content_visibility, :any, default: nil

  @doc "When true, locked/unavailable Layer 2 toggles are shown as disabled. When false (default), they are hidden."
  prop show_unavailable_toggles, :boolean, default: false

  @doc "When true (default), the Custom escape-hatch card is shown alongside the presets."
  prop show_custom_card, :boolean, default: true

  data preset, :string, default: nil
  data layer2, :map, default: %{}
  data layer2_touched, :boolean, default: false
  data advanced_open, :boolean, default: false
  data pending_preset, :string, default: nil

  @doc "Cached config lookups hoisted here so the template doesn't `Config.get` ~20 times per render."
  data preset_dimensions, :map
  data preset_metas, :map
  data preset_slug_list, :list
  data layer2_rows, :list, default: []

  # Tracks first-mount initialisation so re-renders from the parent don't reset
  # the admin's in-progress changes back to the initial_* props.
  data initialised, :boolean, default: false

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(
        :preset_dimensions,
        fn -> Bonfire.Common.Config.get(:preset_dimensions, %{}, :bonfire_boundaries) end
      )
      |> assign_new(:preset_slug_list, fn -> preset_slugs() end)
      |> assign_new(:preset_metas, fn -> Map.new(preset_slugs(), &{&1, preset_meta(&1)}) end)

    socket =
      if socket.assigns.initialised do
        socket
      else
        socket
        |> apply_initial_state()
        |> assign(initialised: true)
      end

    {:ok, socket}
  end

  defp apply_initial_state(socket) do
    a = socket.assigns

    socket
    |> assign(preset: a.initial_preset)
    |> maybe_assign(:membership, a.initial_membership)
    |> maybe_assign(:visibility, a.initial_visibility)
    |> maybe_assign(:participation, a.initial_participation)
    |> maybe_assign(:default_content_visibility, a.initial_default_content_visibility)
    |> Bonfire.Classify.LiveHandler.init_group_boundary_assigns()
    |> maybe_open_advanced(a.initial_preset)
    |> maybe_derive_initial_layer2(a.initial_preset)
    |> assign_layer2_rows(a.initial_preset)
  end

  defp maybe_open_advanced(socket, "custom"), do: assign(socket, advanced_open: true)
  defp maybe_open_advanced(socket, _), do: socket

  defp maybe_derive_initial_layer2(socket, preset) when preset in [nil, "custom"], do: socket

  defp maybe_derive_initial_layer2(socket, _preset) do
    pseudo_preset = %{
      membership: socket.assigns.membership,
      visibility: socket.assigns.visibility,
      participation: socket.assigns.participation,
      default_content_visibility: socket.assigns.default_content_visibility
    }

    assign(socket,
      layer2: derive_layer2_state(pseudo_preset, socket.assigns.preset_dimensions)
    )
  end

  def handle_event("pick_preset", %{"preset" => slug}, %{assigns: a} = socket) do
    cond do
      a.preset == slug ->
        {:noreply, socket}

      is_nil(a.preset) or not a.layer2_touched ->
        {:noreply, apply_preset(socket, slug)}

      true ->
        {:noreply, assign(socket, pending_preset: slug)}
    end
  end

  def handle_event("confirm_preset_change", _, %{assigns: %{pending_preset: slug}} = socket)
      when is_binary(slug) do
    {:noreply,
     socket
     |> apply_preset(slug)
     |> assign(pending_preset: nil)}
  end

  def handle_event("confirm_preset_change", _, socket), do: {:noreply, socket}

  def handle_event("cancel_preset_change", _, socket),
    do: {:noreply, assign(socket, pending_preset: nil)}

  def handle_event("toggle_layer2", %{"key" => key}, %{assigns: a} = socket) do
    key = String.to_existing_atom(key)
    preset = a.preset

    if layer2_locked?(preset, key) do
      {:noreply, socket}
    else
      next = !(Map.get(a.layer2, key) || false)

      {:noreply,
       socket
       |> assign(layer2: Map.put(a.layer2, key, next), layer2_touched: true)
       |> apply_layer2_to_primitives(key, next)}
    end
  end

  def handle_event("toggle_advanced", _, socket),
    do: {:noreply, assign(socket, advanced_open: !socket.assigns.advanced_open)}

  # --- Preset application ---

  defp apply_preset(socket, "custom") do
    socket
    |> assign(preset: "custom", advanced_open: true, layer2: %{}, layer2_touched: false)
    |> assign_layer2_rows("custom")
  end

  defp apply_preset(socket, slug) do
    preset = socket.assigns.preset_metas[slug] || %{}

    socket
    |> assign(
      preset: slug,
      membership: e(preset, :membership, "local:members"),
      visibility: e(preset, :visibility, "local"),
      participation: e(preset, :participation, "local:contributors"),
      default_content_visibility: e(preset, :default_content_visibility, "local"),
      layer2: derive_layer2_state(preset, socket.assigns.preset_dimensions),
      layer2_touched: false
    )
    |> assign_layer2_rows(slug)
  end

  defp assign_layer2_rows(socket, preset),
    do: assign(socket, layer2_rows: layer2_toggle_rows(preset))

  # Toggle initial state is derived from the preset's final dimension slugs by
  # consulting the same `preset_dimensions` config that owns the slug → role/scope
  # mapping. Avoids a parallel set of string-shape rules that would drift when
  # slugs are added or renamed.
  defp derive_layer2_state(preset, preset_dimensions) do
    visibility = e(preset, :visibility, nil)
    vis_options = e(preset_dimensions, :visibility, :options, %{})

    %{
      discoverable: e(vis_options, visibility, :role, nil) == :discover,
      federate: federated_scope?(visibility),
      approval_required: e(preset, :membership, nil) == "on_request",
      anyone_posts: anyone_can_post?(e(preset, :participation, nil))
    }
  end

  # Federated when the visibility's scope isn't one of the on-instance scopes.
  # Uses `slug_to_scope/1` so this stays in sync with the canonical scope list.
  defp federated_scope?(slug) when is_binary(slug),
    do:
      Bonfire.UI.Groups.BoundaryScopeSelectorLive.slug_to_scope(slug) not in [
        "nonfederated",
        "local"
      ]

  defp federated_scope?(_), do: false

  # Open participation: the unscoped "anyone" slug, or any `<scope>:contributors`
  # variant — the contributor suffix is the convention for non-member posting.
  defp anyone_can_post?(slug) when is_binary(slug),
    do: slug == "anyone" or String.ends_with?(slug, ":contributors")

  defp anyone_can_post?(_), do: false

  # --- Layer 2 → primitive mapping (toggle change handlers) ---

  defp apply_layer2_to_primitives(socket, :discoverable, true),
    do: swap_visibility_access(socket, :discover)

  defp apply_layer2_to_primitives(socket, :discoverable, false),
    do: swap_visibility_access(socket, :unlisted_read)

  defp apply_layer2_to_primitives(socket, :approval_required, true),
    do: assign(socket, membership: "on_request")

  defp apply_layer2_to_primitives(socket, :approval_required, false),
    do: assign(socket, membership: "local:members")

  defp apply_layer2_to_primitives(socket, :anyone_posts, true),
    do: assign(socket, participation: "local:contributors")

  defp apply_layer2_to_primitives(socket, :anyone_posts, false),
    do: assign(socket, participation: "group_members")

  # Federate is informational-only until groups federation ships.
  defp apply_layer2_to_primitives(socket, :federate, _), do: socket
  defp apply_layer2_to_primitives(socket, _, _), do: socket

  # Keeps the current visibility scope, but swaps the access role to match the target.
  # Looks up slugs from preset_dimensions config: finds one with the same scope and the given role.
  defp swap_visibility_access(socket, target_role) do
    current_vis = socket.assigns.visibility
    current_scope = Bonfire.UI.Groups.BoundaryScopeSelectorLive.slug_to_scope(current_vis)
    vis_opts = e(socket.assigns.preset_dimensions, :visibility, :options, %{})
    vis_order = e(socket.assigns.preset_dimensions, :visibility, :slug_order, [])

    new_vis =
      Enum.find(vis_order, current_vis, fn slug ->
        Bonfire.UI.Groups.BoundaryScopeSelectorLive.slug_to_scope(slug) == current_scope and
          e(vis_opts, slug, :role, :interact) == target_role
      end)

    assign(socket, visibility: new_vis)
  end

  # --- Layer 2 lock rules (config-driven per preset) ---

  @doc "Whether a Layer 2 toggle is locked for the given preset. Reads from `layer2_locked` in each preset's config."
  def layer2_locked?(preset_slug, key) do
    locked =
      Bonfire.Common.Config.get(
        [:group_presets, preset_slug, :layer2_locked],
        [],
        :bonfire_classify
      )

    key in locked
  end

  def layer2_lock_reason(:federate), do: l("Coming soon: requires groups federation")
  def layer2_lock_reason(_), do: l("Not available for this preset")

  @doc "Returns toggle definitions from config, with `locked` computed for the given preset."
  def layer2_toggle_rows(preset) do
    Bonfire.Common.Config.get(:layer2_toggles, [], :bonfire_classify)
    |> Enum.map(fn %{key: key} = t -> Map.put(t, :locked, layer2_locked?(preset, key)) end)
  end

  # --- Preset list for rendering ---

  def preset_slugs do
    Bonfire.Common.Config.get(:group_preset_order, [], :bonfire_classify)
  end

  def preset_meta(slug) do
    Bonfire.Common.Config.get([:group_presets, slug], %{}, :bonfire_classify)
  end
end
