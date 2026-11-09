defmodule Bonfire.UI.Groups.GroupHeroToggleLive do
  @moduledoc "Unfolds a member's compact `Bonfire.UI.Groups.GroupHeroLive`, client-side."
  use Bonfire.UI.Common.Web, :stateless_component

  @doc "See `Bonfire.UI.Groups.GroupHeroLive.dom_id/2`."
  prop hero_id, :string, required: true
end
