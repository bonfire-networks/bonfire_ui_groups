defmodule Bonfire.UI.Groups.WidgetMembersLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop moderators, :any, default: []
  prop members, :any, default: []
  prop widget_title, :string, default: nil
end
