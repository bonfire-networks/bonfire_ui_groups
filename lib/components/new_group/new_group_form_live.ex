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

  data preset, :string, default: nil
  data layer2, :map, default: %{}
  data layer2_touched, :boolean, default: false
  data advanced_open, :boolean, default: false
  data pending_preset, :string, default: nil

  @doc "Cached config lookups hoisted here so the template doesn't `Config.get` ~20 times per render."
  data preset_dimensions, :map
  data preset_metas, :map

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:preset_dimensions,
       Bonfire.Common.Config.get(:preset_dimensions, %{}, :bonfire_boundaries)
     )
     |> assign(:preset_metas, Map.new(preset_slugs(), &{&1, preset_meta(&1)}))
     |> Bonfire.Classify.LiveHandler.init_group_boundary_assigns()}
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
    do: swap_visibility_access(socket, :discoverable)

  defp apply_layer2_to_primitives(socket, :discoverable, false),
    do: swap_visibility_access(socket, :unlisted)

  defp apply_layer2_to_primitives(socket, :approval_required, true),
    do: assign(socket, membership: "on_request")

  defp apply_layer2_to_primitives(socket, :approval_required, false) do
    # Revert to the preset's default membership; falls back safely when preset is nil or "custom".
    assign(socket,
      membership:
        e(socket.assigns.preset_metas[socket.assigns.preset], :membership, "local:members")
    )
  end

  defp apply_layer2_to_primitives(socket, :anyone_posts, true),
    do: assign(socket, participation: "local:contributors")

  defp apply_layer2_to_primitives(socket, :anyone_posts, false),
    do: assign(socket, participation: "group_members")

  # Federate is informational-only until groups federation ships.
  defp apply_layer2_to_primitives(socket, :federate, _), do: socket
  defp apply_layer2_to_primitives(socket, _, _), do: socket

  defp swap_visibility_access(socket, :discoverable) do
    vis =
      case socket.assigns.visibility do
        "local:unlisted" -> "local:discoverable"
        "local" -> "local:discoverable"
        v -> v
      end

    assign(socket, visibility: vis)
  end

  defp swap_visibility_access(socket, :unlisted) do
    vis =
      case socket.assigns.visibility do
        "local" -> "local:unlisted"
        "local:discoverable" -> "local:unlisted"
        "nonfederated" -> "local:unlisted"
        v -> v
      end

    assign(socket, visibility: vis)
  end

  # --- Layer 2 lock rules (per-preset + global) ---

  @doc "Whether a Layer 2 toggle is locked for the current preset."
  def layer2_locked?(_preset, :federate), do: true

  def layer2_locked?("invite_only_team", key) when key in [:approval_required, :anyone_posts],
    do: true

  def layer2_locked?("private_club", key)
      when key in [:discoverable, :approval_required, :anyone_posts],
      do: true

  def layer2_locked?(_, _), do: false

  def layer2_lock_reason(:federate), do: l("Coming soon: requires groups federation")
  def layer2_lock_reason(_), do: l("Not available for this preset")

  # --- Preset list for rendering ---

  def preset_slugs do
    Bonfire.Common.Config.get(:group_preset_order, [], :bonfire_classify)
  end

  def preset_meta(slug) do
    Bonfire.Common.Config.get([:group_presets, slug], %{}, :bonfire_classify)
  end
end
