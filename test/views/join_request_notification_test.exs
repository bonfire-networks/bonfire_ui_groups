defmodule Bonfire.UI.Groups.JoinRequestNotificationTest do
  @moduledoc """
  A moderator accepting a join request from their notifications, through the page.

  The row's Accept button sends every kind of ask to `Follows.accept/2`, which hands a join request on to `Categories.accept_join_request/3`. Before that, accepting here made a follow and no member, while the group's own requests list worked, which is why it looked like a moderator problem.
  """
  use Bonfire.UI.Groups.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui
  use Bonfire.Common.E

  alias Bonfire.Classify.Simulate
  alias Bonfire.Classify.Categories

  setup do
    creator = fake_user!()
    account = fake_account!()
    moderator = fake_user!(account)
    requester = fake_user!("Hopeful Joiner")

    group =
      Simulate.fake_group!(creator, %{
        membership: "on_request",
        visibility: "members:private",
        participation: "group_members",
        default_content_visibility: "members:private"
      })

    {:ok, _} = Categories.add_moderator(creator, group, id(moderator))
    {:ok, %{requested: true}} = Categories.join_and_follow_group(requester, group)

    {:ok, conn: conn(user: moderator, account: account), requester: requester, group: group}
  end

  test "a moderator accepting a join request from their notifications makes the requester a member and a follower",
       %{conn: conn, requester: requester, group: group} do
    refute Categories.member?(requester, group), "control: not a member before the accept"

    refute Bonfire.Social.Graph.Follows.following?(requester, group),
           "control: not following before the accept, so the follow assertion below proves something"

    conn
    |> visit("/notifications")
    |> wait_async()
    |> assert_has_or_open_browser("[data-id=feed] article", text: "Hopeful Joiner")
    |> click_button("[data-id=feed] article button", "Accept")

    assert Categories.member?(requester, group),
           "accepted from the notification but not made a member"

    assert Bonfire.Social.Graph.Follows.following?(requester, group),
           "accepted as a member but not made a follower, though pressing Join asked for both"
  end

  describe "a join request on its own" do
    # asking to join without asking to follow, so the only ask in the moderator's notifications is the join request, and whatever its row says is about that one
    setup %{group: group} do
      asker = fake_user!("Only Joining")
      {:ok, %{requested: true}} = Categories.join_group(asker, group)
      {:ok, asker: asker}
    end

    for path <- ["/notifications", "/notifications/requests"] do
      test "reads as asking to join the group, in #{path}", %{conn: conn, group: group} do
        conn
        |> visit(unquote(path))
        |> wait_async()
        |> assert_has_or_open_browser("[data-id=feed] article",
          text: "Only Joining requested to join"
        )
        |> refute_has("[data-id=feed] article", text: "Only Joining requested to follow")
        # which group, since a moderator can have several: its preview names it
        |> assert_has("[data-id=feed] article", text: e(group, :profile, :name, nil) || "no name")
        |> refute_has("[data-id=feed] article", text: "Unnamed group")
      end
    end
  end
end
