defmodule Bonfire.UI.Groups.GroupHeroLive do
  use Bonfire.UI.Common.Web, :stateless_component
  import Bonfire.UI.Me.Integration

  prop selected_tab, :any, default: nil
  prop group, :any, required: true
  prop permalink, :any, required: true
  prop object_boundary, :any, default: nil
end
