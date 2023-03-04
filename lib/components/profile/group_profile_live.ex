defmodule Bonfire.UI.Groups.GroupProfileLive do
  use Bonfire.UI.Common.Web, :stateless_component
  alias Bonfire.UI.Me.LivePlugs

  prop selected_tab, :any, default: nil
  prop category, :any, default: nil
  prop hide_tabs, :boolean, default: true

  def tab(selected_tab) do
    case maybe_to_atom(selected_tab) do
      tab when is_atom(tab) -> tab
      _ -> :timeline
    end
    |> debug(selected_tab)
  end
end
