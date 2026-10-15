defmodule Bonfire.UI.Groups.SidebarGroupsLive do
  use Bonfire.UI.Common.Web, :stateful_component

  declare_nav_component("Links to user's groups (and optionally topics)", exclude_from_nav: false)

  # Matches when `current_path` equals `target` exactly, or starts with `target <> "/"` so
  # nested routes (e.g. `/&games/settings`) still highlight the parent group.
  def active_link?(current_path, target)
      when is_binary(current_path) and is_binary(target) do
    current_path == target or String.starts_with?(current_path, target <> "/")
  end

  def active_link?(_, _), do: false

  defp groups(socket) do
    for {%{type: :group} = category, _children} <- e(socket.assigns, :categories, []),
        do: category
  end

  # one query for the whole list, shared by icons and join modes
  defp assign_group_dimensions(socket) do
    dims = Bonfire.Boundaries.Presets.group_listing_dimension_slugs(groups(socket))

    socket
    |> assign(
      :group_icons,
      Map.new(dims, fn {id, d} -> {id, Bonfire.Boundaries.Presets.icon_from_dims(d)} end)
    )
    |> assign(
      :join_modes,
      Map.new(dims, fn {id, d} -> {id, Bonfire.Classify.Categories.join_mode(d.membership)} end)
    )
  end

  # Admin-pinned groups can't be removed from a personal sidebar, so their row menu says so instead
  # of offering an unpin that would silently no-op. One query for the whole list.
  defp assign_instance_pins(socket) do
    assign(
      socket,
      :instance_pinned_ids,
      MapSet.new(Bonfire.Social.Pins.instance_pinned_object_ids())
    )
  end

  # Follow state isn't batched here: passing it down would overwrite each `FollowButtonLive`'s toggled state on re-render, and its `update_many` already batches.
  defp assign_memberships(socket) do
    assign(
      socket,
      :my_memberships,
      Bonfire.Classify.Categories.my_membership_states(
        current_user(socket),
        Enum.map(groups(socket), &id/1)
      )
    )
  end

  # otherwise an admin-pinned private group would offer a follow toggle that fails
  defp assign_followable(socket) do
    assign(
      socket,
      :followable_ids,
      Bonfire.Boundaries.load_pointers(Enum.map(groups(socket), &id/1),
        current_user: current_user(socket),
        verbs: [:follow],
        ids_only: true
      )
      |> MapSet.new(&id/1)
    )
  end

  # Pulls the path once (avoids a per-link URI.parse on every render).
  defp assign_current_path(socket) do
    url = current_url(socket)
    path = is_binary(url) && (URI.parse(url).path || url)
    params = e(socket.assigns, :__context__, :current_params, %{}) || %{}

    socket
    |> assign(:current_path, path || "")
    |> assign(:group_return_to, Bonfire.Classify.Web.GroupNavigation.return_to(params, url))
  end

  # a pin or membership changed elsewhere (routed via PersistentLive)
  def update(%{reload_pins: true}, socket) do
    {:ok,
     socket
     |> assign(categories: pinned_tree(current_user(socket)))
     |> assign_group_dimensions()
     |> assign_instance_pins()
     |> assign_memberships()
     |> assign_followable()}
  end

  def update(assigns, %{assigns: %{categories: _}} = socket) do
    {:ok, socket |> assign(assigns) |> register_for_pin_updates() |> assign_current_path()}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(categories: pinned_tree(current_user(assigns) || current_user(socket)))
     |> assign_group_dimensions()
     |> assign_instance_pins()
     |> assign_memberships()
     |> assign_followable()
     |> register_for_pin_updates()
     |> assign_current_path()}
  end

  # register this component's nav-generated id under the user id so after_pin can reach it via
  # send_updates from within this same (PersistentLive) process (idempotent)
  defp register_for_pin_updates(socket) do
    with user_id when is_binary(user_id) <- current_user_id(socket),
         id when not is_nil(id) <- e(socket.assigns, :id, nil) do
      Bonfire.UI.Common.ComponentID.register_alias(__MODULE__, user_id, id)
    end

    socket
  end

  defp pinned_tree(user), do: Bonfire.Classify.my_pinned_tree(user) || []
end
