defmodule Bonfire.UI.Groups.GroupHeroLive do
  @moduledoc """
  The group page header: banner, avatar, name, address, description, then a row with the member count and the actions. Compact for members. Only the actions depend on the viewer: Join (or Pending) and follow for visitors; their membership as a status, the bell and ⋯ (follow, leave) for members. The page header above stays as the sticky bar, so back and the sidebar toggle live there.

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

  @doc "`:preview` for a viewer who may see the group but not read it: the header stays folded, with no banner, description or members, and no toggle to expand it (see `page_header_assigns/3`)."
  prop view_mode, :atom, default: :full

  @doc "Show the actions (Join, follow, the member's menu). Off where the page offers them itself, eg. inside `Bonfire.UI.Topics.TopicAccessGateLive`."
  prop actions, :boolean, default: true

  @doc "Whether the viewer may see the list of members (`Bonfire.Classify.Categories.roster_visible?/2`, assigned once by the page). Otherwise the pill shows the moderators and no total."
  prop roster_visible, :boolean, default: true

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

  @doc "The page shows its sensitive notice (`Bonfire.UI.Groups.SensitiveNoticeLive`), so the banner and avatar are blurred until \"Continue\"."
  prop sensitive_notice, :boolean, default: false

  @doc "The viewer's pin state for the ⋯ menu, see `Bonfire.UI.Groups.GroupHeroActionsLive`."
  prop pins, :map, default: %{instance: false, sidebar: false, can_pin_instance: false}

  def render(assigns) do
    assigns
    |> assign(
      avatar_url: Media.avatar_url(assigns.group),
      banner_url: Media.banner_url(assigns.group, fallback: false),
      variant: variant(assigns.my_membership),
      preview: assigns.view_mode == :preview,
      # `group` has `character: [:peered]` preloaded by the page (`load_category/4`)
      remote: not Bonfire.Social.is_local?(assigns.group),
      faces: faces(assigns.roster_visible, assigns.members, assigns.moderators)
    )
    |> render_sface()
  end

  @doc """
  The count of a group's members for display. A group hosted elsewhere is counted as far as we know its members (those of ours who joined it, and those its origin names), so it says so.

  ## Examples

      iex> Bonfire.UI.Groups.GroupHeroLive.member_count_label(1, false)
      "1 member"

      iex> Bonfire.UI.Groups.GroupHeroLive.member_count_label(2, true)
      "2 known members"
  """
  def member_count_label(count, remote?) when is_integer(count) do
    if remote?,
      do: lp("%{count} known member", "%{count} known members", count, count: count),
      else: lp("%{count} member", "%{count} members", count, count: count)
  end

  @doc """
  The avatars in the members pill: the first members for whoever may see the list, else the (already loaded) moderators, as the members tab lists only those to them.

      iex> Bonfire.UI.Groups.GroupHeroLive.faces(true, [%{id: "m"}], [%{id: "o"}])
      [%{id: "m"}]
      iex> Bonfire.UI.Groups.GroupHeroLive.faces(false, [%{id: "m"}], [%{id: "o"}])
      [%{id: "o"}]
  """
  def faces(true, members, _moderators), do: members
  def faces(_roster_visible, _members, moderators), do: Enum.take(moderators, 5)

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
  The hero's DOM id, per variant so joining resets the toggle.

      iex> Bonfire.UI.Groups.GroupHeroLive.dom_id(%{id: "01G"}, "member")
      "group_hero-01G-member"
  """
  def dom_id(group, variant), do: "group_hero-#{id(group)}-#{variant}"

  @doc """
  A member's header avatar and toggle, a preview viewer's avatar without the toggle (their header has nothing to expand), else `[]`.

      iex> Bonfire.UI.Groups.GroupHeroLive.page_header_assigns(%{id: "01G"}, false)
      []
      iex> Bonfire.UI.Groups.GroupHeroLive.page_header_assigns(nil, true)
      []
      iex> Bonfire.UI.Groups.GroupHeroLive.page_header_assigns(%{id: "01G"}, false, :preview)[:page_header_aside]
      nil
  """
  def page_header_assigns(group, my_membership, view_mode \\ :full) do
    cond do
      is_nil(group) ->
        []

      variant(my_membership) == "member" ->
        [
          page_header_icon: page_header_icon(group),
          page_header_aside: [
            {Bonfire.UI.Groups.GroupHeroToggleLive, [hero_id: dom_id(group, "member")]}
          ]
        ]

      view_mode == :preview ->
        [page_header_icon: page_header_icon(group), page_header_aside: nil]

      true ->
        []
    end
  end

  # The header assigns come from the viewer's variant and view mode (members: avatar and toggle; preview viewers: avatar only). Replaced:
  # def page_header_assigns(group, my_membership) do
  #   if group && variant(my_membership) == "member" do
  #     [page_header_icon: %{...}, page_header_aside: [{Bonfire.UI.Groups.GroupHeroToggleLive, [hero_id: dom_id(group, "member")]}]]
  #   else
  #     []
  #   end
  # end

  defp page_header_icon(group) do
    %{
      id: id(group),
      object: group,
      # nil without an avatar, so the header draws the group's tile
      src: if((url = Media.avatar_url(group)) != "/images/avatar.png", do: url),
      name: e(group, :profile, :name, nil)
    }
  end

  @doc """
  Assigns `page_header_assigns/3`, clearing only its own toggle.
  """
  def assign_page_header(socket, group, my_membership, view_mode \\ :full) do
    case page_header_assigns(group, my_membership, view_mode) do
      [] ->
        if toggle_aside?(e(assigns(socket), :page_header_aside, nil)),
          do: assign(socket, page_header_icon: nil, page_header_aside: nil),
          else: socket

      header ->
        assign(socket, header)
    end
  end

  @doc """
  Whether the aside holds the hero toggle.

      iex> Bonfire.UI.Groups.GroupHeroLive.toggle_aside?([{Bonfire.UI.Groups.GroupHeroToggleLive, []}])
      true
      iex> Bonfire.UI.Groups.GroupHeroLive.toggle_aside?([{Bonfire.Notify.Web.BellButtonLive, []}])
      false
      iex> Bonfire.UI.Groups.GroupHeroLive.toggle_aside?(nil)
      false
  """
  def toggle_aside?(aside) when is_list(aside),
    do: Enum.any?(aside, &match?({Bonfire.UI.Groups.GroupHeroToggleLive, _}, &1))

  def toggle_aside?(_), do: false

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
