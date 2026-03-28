defmodule Bonfire.UI.Groups.DiscoverGroupsLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop categories, :list, default: []
  prop page_info, :any, default: nil
  prop search_term, :string, default: ""
end
