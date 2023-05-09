defmodule Bonfire.UI.Groups.SidebarGroupLive do
  use Bonfire.UI.Common.Web, :stateless_component
  import Bonfire.UI.Me.Integration
  prop category, :any, required: true
  prop children, :list, default: []
end
