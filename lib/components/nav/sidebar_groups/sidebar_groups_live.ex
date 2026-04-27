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

  defdelegate group_icon(group), to: Bonfire.Boundaries.Presets

  # Pulls the path once (avoids a per-link URI.parse on every render).
  defp assign_current_path(socket) do
    url = current_url(socket)
    path = is_binary(url) && (URI.parse(url).path || url)
    assign(socket, :current_path, path || "")
  end

  def update(assigns, %{assigns: %{categories: _}} = socket) do
    debug("categories already loaded")

    {:ok, socket |> assign(assigns) |> assign_current_path()}
  end

  def update(assigns, socket) do
    # TODO: pagination
    {followed_categories, page_info} =
      Bonfire.Classify.my_followed_tree(current_user(assigns) || current_user(socket),
        pagination: %{limit: 500}
      )

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       categories: followed_categories || [],
       page_info: page_info
     )
     |> assign_current_path()}
  end
end
