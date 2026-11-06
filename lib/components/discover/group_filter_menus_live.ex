defmodule Bonfire.UI.Groups.GroupFilterMenusLive do
  @moduledoc "The filter menus of the /groups form (`Bonfire.UI.Groups.GroupFiltersLive.menus/1`), which sit beside the search box on the directory views and at the end of the view tabs on the feed views."
  use Bonfire.UI.Common.Web, :stateless_component

  @doc "`{field, id, icon, options, value, default_value, legend}` for each menu, from `Bonfire.UI.Groups.GroupFiltersLive.menus/1`"
  prop menus, :list, default: []
  @doc "The /groups filters form, which names each menu's radios"
  prop form, :any, required: true
  prop class, :css_class, default: "flex items-center gap-1"
end
