defmodule Bonfire.UI.Groups.LiveHandler do
  use Bonfire.UI.Common.Web, :live_handler

  def handle_event("toggle_groups_nav_visibility", _params, socket) do
    # Toggle is handled client-side by <details> natively;
    # persisting to settings is best-effort
    {:noreply, socket}
  end

  def handle_event("new", %{} = attrs, socket) do
    Bonfire.Classify.LiveHandler.new(:group, attrs, socket)
  end

  def handle_event("autocomplete", %{"input" => input}, _socket) do
    # TODO?
  end

  def handle_event("edit", _attrs, _socket) do
    # TODO?
  end
end
