defmodule Bonfire.UI.Groups.GroupHeroLive do
  use Bonfire.UI.Common.Web, :stateless_component
  import Bonfire.UI.Me.Integration

  prop selected_tab, :string
  # alias Bonfire.Boundaries.Circles

  # prop scope, :atom, default: nil
  # prop myself, :map, default: nil
  # prop setting_boundaries, :boolean, default: false
end
