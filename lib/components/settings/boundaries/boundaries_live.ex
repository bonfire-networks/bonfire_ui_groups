defmodule Bonfire.UI.Groups.Settings.BoundariesLive do
  use Bonfire.UI.Common.Web, :stateful_component

  prop selected_tab, :any, default: nil
  prop category, :any, required: true
  prop boundary_preset, :any, default: nil

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> Bonfire.Classify.LiveHandler.init_group_boundary_assigns()}
  end
end
