defmodule Bonfire.UI.Groups.GroupHeroLive do
  @moduledoc """
  The group page header, the same for everyone: banner, avatar, name, address, description, then a row with the member count and the actions. Only the actions depend on the viewer: Join (or Pending) and follow for visitors; their membership as a status, the bell and ⋯ (follow, leave) for members. The page header above stays as the sticky bar, so back and the sidebar toggle live there.

  The banner shows at its stored 3:1 ratio (`Bonfire.Files.BannerUploader`). Which actions show is the viewer's membership (`my_membership`, from `Bonfire.Classify.LiveHandler`), not `view_mode`: a non-member of an open public group can read everything and still needs Join.
  """
  use Bonfire.UI.Common.Web, :stateless_component

  prop group, :any, required: true
  prop permalink, :any, default: nil

  prop moderators, :list, default: []

  @doc "The first few members, for the facepile (see `Bonfire.Classify.Categories.list_members/2`)."
  prop members, :list, default: []

  @doc "`true`, `:requested` or `false`, see `Bonfire.Classify.Categories.my_membership_states/2`."
  prop my_membership, :any, default: false

  prop membership_slug, :string, default: nil
  prop member_count, :integer, default: 0
  prop subcategories, :list, default: []
  prop group_return_to, :string, default: "/groups"

  @doc "On a topic page inside the group, that topic, whose chip is current and opens its actions."
  prop selected_topic, :any, default: nil

  @doc "Offer New topic in the topic row, see `Bonfire.Classify.can_create_topic?/2`."
  prop can_create_topic, :boolean, default: false

  @doc "Offer Topic settings in the selected chip's menu, decided by the page."
  prop can_edit_topic, :boolean, default: false

  @doc "The viewer's pin state for the ⋯ menu, see `Bonfire.UI.Groups.GroupHeroActionsLive`."
  prop pins, :map, default: %{instance: false, sidebar: false, can_pin_instance: false}

  def render(assigns) do
    assigns
    |> assign(
      avatar_url: Media.avatar_url(assigns.group),
      banner_url: Media.banner_url(assigns.group, fallback: false),
      variant: variant(assigns.my_membership)
    )
    |> render_sface()
  end

  @doc """
  Which actions to show: members get theirs, everyone else (including someone with a pending request) Join.

      iex> Bonfire.UI.Groups.GroupHeroLive.variant(true)
      "member"
      iex> Bonfire.UI.Groups.GroupHeroLive.variant(:requested)
      "visitor"
      iex> Bonfire.UI.Groups.GroupHeroLive.variant(false)
      "visitor"
  """
  def variant(true), do: "member"
  def variant(_), do: "visitor"

  @doc """
  Whether the viewer is one of the group's (already loaded) moderators, so no boundary query runs per render.

      iex> Bonfire.UI.Groups.GroupHeroLive.moderator?("01M5A1RS1M5A1RS1M5A1RS1M5", [%{id: "01M5A1RS1M5A1RS1M5A1RS1M5"}])
      true
      iex> Bonfire.UI.Groups.GroupHeroLive.moderator?(nil, [%{id: "01M5A1RS1M5A1RS1M5A1RS1M5"}])
      false
  """
  def moderator?(current_user_id, moderators)
      when is_binary(current_user_id) and is_list(moderators),
      do: current_user_id in Enums.ids(moderators)

  def moderator?(_, _), do: false

  @doc "Short labels for the access line. Two membership presets read better in the header than their settings-form wording."
  def hero_dimension_label(:membership, "open", _meta), do: l("Open to join")
  def hero_dimension_label(:membership, "local:members", _meta), do: l("Local users can join")
  def hero_dimension_label(_dimension, _slug, meta), do: e(meta, :label, nil)
end
