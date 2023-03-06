defmodule Bonfire.UI.Groups.DiscoverGroupLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop category, :any, required: true
  prop children, :list, default: []
end
