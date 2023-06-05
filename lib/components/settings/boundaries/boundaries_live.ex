defmodule Bonfire.UI.Groups.Settings.BoundariesLive do
  use Bonfire.UI.Common.Web, :stateless_component
  alias Bonfire.Boundaries.Acls

  prop selected_tab, :any, default: nil
  prop category, :any, required: true
  prop boundary_preset, :any, default: nil
end
