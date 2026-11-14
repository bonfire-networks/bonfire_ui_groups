defmodule Bonfire.UI.Groups.GroupAddressLive do
  @moduledoc "A group's or topic's full federated address (`name@instance`, no prefix), shown whole, wrapping instead of truncating, since a cut-off address can't be searched for from another server. A dropdown copies it as `!name@instance` (Lemmy and others), `@name@instance` (Mastodon and others) or the link."
  use Bonfire.UI.Common.Web, :stateless_component

  prop group, :any, required: true

  @doc "Makes the DOM id unique when the address shows more than once on a page (the header and the group widget's fediverse section): the `Copy` hook needs one."
  prop id_prefix, :string, default: "group-address"

  prop class, :css_class, default: "text-sm text-muted"

  def render(assigns) do
    assigns
    # no prefix: the dropdown's entries add the one each kind of server expects
    # `canonical_url` reads `character.peered`, which the callers' pages preload; a loaded `nil` (a local group) is generated without a query
    |> assign(
      address: Bonfire.Me.Characters.display_username(assigns.group, true, nil, ""),
      link: Bonfire.Common.URIs.canonical_url(assigns.group)
    )
    # |> assign(:address, Bonfire.Me.Characters.display_username(assigns.group, true))
    |> render_sface()
  end
end
