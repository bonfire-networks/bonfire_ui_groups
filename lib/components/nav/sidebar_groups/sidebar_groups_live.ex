defmodule Bonfire.UI.Groups.SidebarGroupsLive do
  use Bonfire.UI.Common.Web, :stateful_component

  declare_nav_component("Links to user's groups (and optionally topics)", exclude_from_nav: false)

  def update(_assigns, %{assigns: %{categories: _}} = socket) do
    debug("categories already loaded")

    {:ok, socket}
  end

  def update(assigns, socket) do
    # TODO: pagination
    {followed_categories, page_info} =
      Bonfire.Classify.my_followed_tree(current_user(assigns), pagination: %{limit: 500})

    {:ok,
     assign(
       socket,
       categories: followed_categories || [],
       page_info: page_info
     )}
  end
end
