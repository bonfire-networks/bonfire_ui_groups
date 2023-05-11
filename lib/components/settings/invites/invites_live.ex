defmodule Bonfire.UI.Groups.Settings.InvitesLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop selected_tab, :any, default: nil
  prop category, :any, required: true
end
