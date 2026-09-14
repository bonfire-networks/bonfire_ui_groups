defmodule Bonfire.UI.Groups.DiscoverGroupsLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop categories, :list, default: []
  prop previews, :map, default: %{}
  prop page_info, :any, default: nil
  prop search_term, :string, default: ""
  prop join_filter, :string, default: "all"

  prop selected_tab, :string, default: "discover"
end
