defmodule Bonfire.UI.Groups.DiscoverGroupsLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop categories, :list, default: []
  prop previews, :map, default: %{}
  prop page_info, :any, default: nil
  prop search_term, :string, default: ""

  @doc "The fediverse lookup of a typed handle or URL: nil, or `%{q: q, status: :searching | :found | :not_group | :not_found}`"
  prop group_lookup, :any, default: nil
  prop join_filter, :string, default: "all"
  prop origin, :string, default: "all"

  prop selected_tab, :string, default: "discover"
end
