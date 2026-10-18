defmodule Bonfire.UI.Groups.GroupAddressLive do
  @moduledoc "A group's full federated address (eg. `&name@instance`), copyable. Shown whole, wrapping instead of truncating, since a cut-off address can't be searched for from another server."
  use Bonfire.UI.Common.Web, :stateless_component

  prop group, :any, required: true

  @doc "Makes the DOM id unique when the address shows more than once on a page (the header and the group widget's fediverse section): the `Copy` hook needs one."
  prop id_prefix, :string, default: "group-address"

  prop class, :css_class, default: "text-sm text-muted"

  def render(assigns) do
    assigns
    |> assign(:address, Bonfire.Me.Characters.display_username(assigns.group, true))
    |> render_sface()
  end
end
