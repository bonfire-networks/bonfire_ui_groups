defmodule Bonfire.UI.Groups.DiscoverGroupsLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop categories, :list, default: []

  slot header
end
