defmodule Bonfire.UI.Groups.InstanceSidebarPinLive do
  @moduledoc """
  Instance-admin toggle to pin/unpin a group to EVERYONE's sidebar (instance-scope pin, via the
  shared `Bonfire.Social.Pins:pin` handler → `after_pin`). Gated to `:mediate, :instance` — the verb
  `Pins` enforces — so instance admins/mods can curate the sidebar for any group from its profile
  hero, without being a moderator of that group (i.e. without reaching its settings page).
  """
  use Bonfire.UI.Common.Web, :stateless_component

  prop group, :any, required: true
  prop class, :css_class, default: nil
end
