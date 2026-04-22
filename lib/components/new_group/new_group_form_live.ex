defmodule Bonfire.UI.Groups.NewGroupFormLive do
  @moduledoc """
  Interactive form for creating a new group, structured as three-layer progressive disclosure
  (see `docs/topics/DESIGN.md`). Rendered as a stateful child of `OpenModalLive` so that state
  updates re-render inside the reusable modal — an outer component holding this state would be
  frozen at modal-open time.

  Layer 1: audience presets.
  Layer 2: aggregated toggles (discoverable / federate / approval / anyone posts).
  Layer 3: per-dimension matrix, collapsed behind Advanced.
  """

  use Bonfire.UI.Common.Web, :stateful_component

  prop parent, :any, default: nil
  prop parent_id, :any, default: nil

  @doc "When true, locked/unavailable Layer 2 toggles are shown as disabled. When false (default), they are hidden."
  prop show_unavailable_toggles, :boolean, default: false

  data preset, :string, default: nil
  data layer2, :map, default: %{}
  data layer2_touched, :boolean, default: false
  data advanced_open, :boolean, default: false
  data pending_preset, :string, default: nil

  @doc "Cached config lookups hoisted here so the template doesn't `Config.get` ~20 times per render."
  data preset_dimensions, :map
  data preset_metas, :map

  def update(assigns, socket) do
    default_preset =
      Bonfire.Common.Config.get(:group_default_preset, nil, :bonfire_classify) ||
        Enum.find(preset_slugs(), &(preset_meta(&1) != %{})) ||
        "private_club"

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       :preset_dimensions,
       Bonfire.Common.Config.get(:preset_dimensions, %{}, :bonfire_boundaries)
     )
     |> assign(:preset_metas, Map.new(preset_slugs(), &{&1, preset_meta(&1)}))
     |> Bonfire.Classify.LiveHandler.init_group_boundary_assigns()
     |> then(fn s ->
       if is_nil(s.assigns[:preset]), do: apply_preset(s, default_preset), else: s
     end)}
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
    assign(socket,
      preset: "custom",
      advanced_open: true,
      layer2: %{},
      layer2_touched: false
    )
  end

  defp apply_preset(socket, slug) do
    preset = socket.assigns.preset_metas[slug] || %{}

    assign(socket,
      preset: slug,
      membership: e(preset, :membership, "local:members"),
      visibility: e(preset, :visibility, "local"),
      participation: e(preset, :participation, "local:contributors"),
      default_content_visibility: e(preset, :default_content_visibility, "local"),
      layer2: e(preset, :layer2_defaults, %{}),
      layer2_touched: false
    )
  end

  # --- Layer 2 → primitive mapping ---

  defp apply_layer2_to_primitives(socket, :discoverable, true),
    do: swap_visibility_access(socket, :discover)

  defp apply_layer2_to_primitives(socket, :discoverable, false),
    do: swap_visibility_access(socket, :unlisted_read)

  defp apply_layer2_to_primitives(socket, :approval_required, true),
    do: assign(socket, membership: "on_request")

  defp apply_layer2_to_primitives(socket, :approval_required, false) do
    preset_meta = socket.assigns.preset_metas[socket.assigns.preset] || %{}

    assign(socket,
      membership: e(preset_meta, :membership_open, e(preset_meta, :membership, "local:members"))
    )
  end

  defp apply_layer2_to_primitives(socket, :anyone_posts, true) do
    preset_meta = socket.assigns.preset_metas[socket.assigns.preset] || %{}
    assign(socket, participation: e(preset_meta, :participation_open, "local:contributors"))
  end

  defp apply_layer2_to_primitives(socket, :anyone_posts, false) do
    preset_meta = socket.assigns.preset_metas[socket.assigns.preset] || %{}
    assign(socket, participation: e(preset_meta, :participation, "group_members"))
  end

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
