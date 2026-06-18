defmodule Bonfire.UI.Groups.SidebarGroupsOrderLive do
  @moduledoc """
  Instance-admin settings control to order (drag) and unpin the groups pinned to everyone's sidebar.
  Each reorder writes a rank via `Pins.rank_pin(_, :instance, _)`; unpin removes the instance pin.
  Shown on `/settings/instance/bonfire_ui_groups` (and only to users with `:mediate, :instance`).
  """
  use Bonfire.UI.Common.Web, :stateful_component

  declare_settings_component("Sidebar order",
    icon: "ph:list-bullets-duotone",
    description: "Order and remove the groups pinned to everyone's sidebar.",
    scope: :instance
  )

  # props passed by the settings WidgetsLive wrapper
  prop selected_tab, :any, default: nil
  prop page, :any, default: nil
  prop showing_within, :any, default: nil
  prop compact, :boolean, default: false
  prop scope, :any, default: nil
  prop parent_id, :string, default: "sidebar_groups_order"

  def update(assigns, socket) do
    {:ok, socket |> assign(assigns) |> assign(groups: Bonfire.Classify.instance_pinned_groups())}
  end

  # The Draggable hook also sends `target_order` (the whole new order), but we don't need it: ranking
  # only the moved item at its `new_index` is sufficient AND correct — ecto_ranked excludes the moved
  # row and ranks it between its neighbours at that index (verified for front/middle/end moves).
  def handle_event(
        "reorder_sidebar_groups",
        %{"source_item" => group_id, "new_index" => new_index},
        socket
      ) do
    if admin?(socket), do: Bonfire.Social.Pins.rank_pin(group_id, :instance, new_index)
    {:noreply, reload(socket)}
  end

  def handle_event("unpin_instance", %{"id" => group_id}, socket) do
    if admin?(socket), do: Bonfire.Social.Pins.unpin(current_user(socket), group_id, :instance)
    {:noreply, reload(socket)}
  end

  defp admin?(socket), do: Bonfire.Boundaries.can?(current_user(socket), :mediate, :instance)
  defp reload(socket), do: assign(socket, groups: Bonfire.Classify.instance_pinned_groups())
end
