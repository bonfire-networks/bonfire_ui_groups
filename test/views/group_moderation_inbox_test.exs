defmodule Bonfire.UI.Groups.GroupModerationInboxTest do
  @moduledoc """
  A group's moderation page (`/group/<username>/settings/moderation`) shows the group's inbox, the same feed as its "submitted" view, so a moderator finds everything waiting on them in one place: reports on what's posted in the group, join requests, and posts submitted to it.

  Reports are for moderators only. Flags are left out of feeds unless asked for (`include_flags`), so the group's public inbox (`/group/<username>/submitted`, left to per-object boundaries) must not show them to anyone else.
  """
  use Bonfire.UI.Groups.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  alias Bonfire.Classify.Simulate
  alias Bonfire.Classify.Categories

  setup do
    Process.put(:federating, false)

    # the test page size is 2, and the inbox holds more than that (follows, the join request, the report)
    Process.put([:bonfire, :default_pagination_limit], 10)

    creator = fake_user!(fake_account!())
    moderator_account = fake_account!()
    moderator = fake_user!(moderator_account)
    member_account = fake_account!()
    member = fake_user!(member_account, %{name: "Plain Member"})
    reporter = fake_user!(fake_account!())
    requester = fake_user!(fake_account!(), %{name: "Hopeful Joiner"})

    group =
      Simulate.fake_group!(creator, %{
        membership: "on_request",
        visibility: "global",
        participation: "group_members",
        default_content_visibility: "public"
      })

    # a promoted moderator, not the creator, who could pass on being the group's creator alone
    {:ok, _} = Categories.add_moderator(creator, group, id(moderator))
    {:ok, _} = Categories.add_member(creator, group, id(member))

    post = Simulate.fake_post_in_group!(member, group, "<p>Reported post</p>")

    {:ok, _} =
      Bonfire.Social.Flags.flag(reporter, post, comment: "Please look at this report")

    {:ok, %{requested: true}} = Categories.join_and_follow_group(requester, group)

    {:ok,
     group: group,
     moderator: moderator,
     moderator_account: moderator_account,
     member: member,
     member_account: member_account}
  end

  test "a moderator sees reports and join requests on the group's moderation page", %{
    group: group,
    moderator: moderator,
    moderator_account: moderator_account
  } do
    conn(user: moderator, account: moderator_account)
    |> visit("/group/#{group.character.username}/settings/moderation")
    |> wait_async()
    |> assert_has_or_open_browser("[data-id=feed] article", text: "Reported post")
    |> assert_has("[data-id=feed] article", text: "Hopeful Joiner")
  end

  test "someone who doesn't moderate the group doesn't see its reports in the group's inbox", %{
    group: group,
    member: member,
    member_account: member_account
  } do
    conn(user: member, account: member_account)
    |> visit("/group/#{group.character.username}/submitted")
    |> wait_async()
    # the control: the inbox did load and show what this member may see (an activity about the group; not the join request, which isn't theirs to see), so a missing report is the boundary, not an empty page
    |> assert_has_or_open_browser("[data-id=feed] article", text: group.profile.name)
    |> refute_has("[data-id=feed] article", text: "Please look at this report")
  end
end
