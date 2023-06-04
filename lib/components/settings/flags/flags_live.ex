defmodule Bonfire.UI.Groups.Settings.FlagsLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop selected_tab, :any, default: nil
  prop category, :any, required: true
end
