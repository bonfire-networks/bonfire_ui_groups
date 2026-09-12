defmodule Bonfire.UI.Groups.GroupTopicsNavLive do
  @moduledoc "Group topic links, arranged vertically in the sidebar or horizontally on mobile. Hidden when there are no topics."
  use Bonfire.UI.Common.Web, :stateless_component

  prop group, :any, required: true
  prop topics, :list, default: []
  prop group_return_to, :string, default: "/groups"
  prop inline, :boolean, default: false
end
