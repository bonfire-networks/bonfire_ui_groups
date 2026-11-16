defmodule Bonfire.UI.Groups.GroupAddressLive do
  @moduledoc "A group's or topic's full federated address, shown whole, wrapping instead of truncating, since a cut-off address can't be searched for from another server. A dropdown copies it as `name@instance`, `!name@instance` (Lemmy and others), `@name@instance` (Mastodon and others) or the link. A signed-in user's pick is saved as their setting, and the address then shows in that form, with that form first in the dropdown; a guest sees `name@instance` and nothing is saved."
  use Bonfire.UI.Common.Web, :stateless_component

  prop group, :any, required: true

  @doc "Makes the DOM id unique when the address shows more than once on a page (the header and the group widget's fediverse section): the `Copy` hook needs one."
  prop id_prefix, :string, default: "group-address"

  prop class, :css_class, default: "text-sm text-muted"

  @default_form "plain"
  # the forms that show as text and can be saved; the link is only ever copied
  @address_forms ~w(plain bang at)
  @prefixes %{"plain" => "", "bang" => "!", "at" => "@"}
  @dom_suffixes %{"plain" => "plain", "bang" => "lemmy", "at" => "mastodon", "link" => "link"}

  @doc "The setting's value (one of `#{inspect(@address_forms)}`) from the viewer's loaded settings (the context), so no query per render; anything else, or no user, is the plain form."
  def address_form(context) do
    # `Settings.put` stores a string value as an atom, so it reads back as either
    case to_string(
           Bonfire.Common.Settings.get([:ui, :group_address_form], @default_form, context)
         ) do
      form when form in @address_forms -> form
      _ -> @default_form
    end
  end

  def render(assigns) do
    form = address_form(assigns[:__context__])
    # no prefix: each row adds the one its kind of server expects
    # `canonical_url` reads `character.peered`, which the callers' pages preload; a loaded `nil` (a local group) is generated without a query
    address = Bonfire.Me.Characters.display_username(assigns.group, true, nil, "")
    link = Bonfire.Common.URIs.canonical_url(assigns.group)

    rows =
      @address_forms
      |> Enum.map(&%{form: &1, value: @prefixes[&1] <> address})
      |> Kernel.++(if link, do: [%{form: "link", value: link}], else: [])
      # the DOM ids keep the suffixes the rows had before they were named by form
      |> Enum.map(&Map.put(&1, :dom_suffix, @dom_suffixes[&1.form]))
      # the saved form first
      |> Enum.sort_by(&(&1.form != form))

    assigns
    |> assign(
      address: address,
      shown_address: @prefixes[form] <> address,
      rows: rows,
      # a guest's pick would have nowhere to be saved
      save?: not is_nil(current_user_id(assigns[:__context__]))
    )
    |> render_sface()
  end
end
