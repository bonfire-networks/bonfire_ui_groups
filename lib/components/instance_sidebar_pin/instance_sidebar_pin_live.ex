defmodule Bonfire.UI.Groups.InstanceSidebarPinLive do
  @moduledoc """
  Pins or unpins a group to everyone's sidebar (an instance-scope pin, through the shared `Bonfire.Social.Pins:pin` handler). The caller shows it only to holders of `:mediate` on the instance, the verb `Pins` checks.
  """
  use Bonfire.UI.Common.Web, :stateless_component

  prop group, :any, required: true
  prop class, :css_class, default: nil

  @doc "Whether the group is pinned to everyone's sidebar, read by the page once."
  prop pinned?, :boolean, default: false
end
