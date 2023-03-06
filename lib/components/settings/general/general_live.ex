defmodule Bonfire.UI.Groups.Settings.GeneralLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop selected_tab, :any, default: nil
  prop group, :any, required: true

end
