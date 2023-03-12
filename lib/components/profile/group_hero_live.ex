defmodule Bonfire.UI.Groups.GroupHeroLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop selected_tab, :any, default: nil
  prop group, :any, required: true
  prop permalink, :any, required: true
  prop object_boundary, :any, default: nil
end
