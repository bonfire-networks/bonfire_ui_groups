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

  # Active-state label classes — evaluates active_link?/2 once per row (not twice in the template)
  def group_label_class(current_path, target) do
    if active_link?(current_path, target),
      do: "font-semibold text-primary",
      else: "font-normal text-base-content"
  end

  defdelegate group_icon(group), to: Bonfire.Boundaries.Presets

  # Pulls the path once (avoids a per-link URI.parse on every render).
  defp assign_current_path(socket) do
    url = current_url(socket)
    path = is_binary(url) && (URI.parse(url).path || url)
    assign(socket, :current_path, path || "")
  end

  # a pin changed elsewhere → recompute reactively (routed via PersistentLive, see after_pin)
  def update(%{reload_pins: true}, socket) do
    {:ok, assign(socket, categories: pinned_tree(current_user(socket)))}
  end

  def update(assigns, %{assigns: %{categories: _}} = socket) do
    {:ok, socket |> assign(assigns) |> register_for_pin_updates() |> assign_current_path()}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(categories: pinned_tree(current_user(assigns) || current_user(socket)))
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
