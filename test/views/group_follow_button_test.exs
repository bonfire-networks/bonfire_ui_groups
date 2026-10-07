defmodule Bonfire.UI.Groups.GroupFollowButtonTest do
  @moduledoc """
  The round Follow button on a group's page, for someone who already joined it. Joining also follows the group (`Categories.join_and_follow_group/2`), so the button has to say so, and act on it.
  """
  use Bonfire.UI.Groups.ConnCase, async: false
  @moduletag :ui

  alias Bonfire.Classify.Categories
  alias Bonfire.Social.Graph.Follows

  setup do
    owner = fake_user!()
    account = fake_account!()
    member = fake_user!(account)

    group =
      Bonfire.Classify.Simulate.fake_group!(owner, %{
        name: "Joined club",
        membership: "open",
        visibility: "global",
        participation: "anyone",
        default_content_visibility: "public"
      })

    assert {:ok, _} = Categories.join_and_follow_group(member, group)

    assert Follows.following?(member, group),
           "control: joining follows the group, so the button has something to show"

    %{group: group, member: member, account: account}
  end

  # the ROUND Follow in the group's hero (icon only, `JoinButtonLive`'s combined mode), told apart from any other follow toggle on the page by its tooltip
  @round_following "button[data-id=unfollow][data-tip='Unfollow group']"
  @round_not_following "[data-id=follow][data-tip='Follow group']"

  test "a member sees the group's round Follow as following", context do
    conn(user: context.member, account: context.account)
    |> visit(Bonfire.Common.URIs.path(context.group))
    |> wait_async()
    |> assert_has_or_open_browser(@round_following)
    |> refute_has(@round_not_following)
  end

  test "a member's click on the group's round Follow unfollows it, without an error", context do
    conn(user: context.member, account: context.account)
    |> visit(Bonfire.Common.URIs.path(context.group))
    |> wait_async()
    |> click_button(@round_following, "")
    |> refute_has("*", text: "error")

    refute Follows.following?(context.member, context.group),
           "the click unfollowed the group"
  end

  # a member let in by a moderator: joining an on-request group REQUESTS both the membership and the follow, and accepting the membership must not leave the follow a pending request the button can't show
  test "a member accepted into an on-request group sees its round Follow as it is, and clicking it gives no error" do
    owner = fake_user!()
    account = fake_account!()
    member = fake_user!(account)

    group =
      Bonfire.Classify.Simulate.fake_group!(owner, %{
        name: "Approval club",
        membership: "on_request",
        visibility: "global",
        participation: "group_members",
        default_content_visibility: "public"
      })

    assert {:ok, %{requested: true}} = Categories.join_and_follow_group(member, group)

    {:ok, request} =
      Bonfire.Social.Requests.get(member, Bonfire.Boundaries.Verbs.get_id!(:join), group,
        current_user: owner
      )

    assert {:ok, _} = Categories.accept_join_request(owner, request)
    assert Categories.member?(member, group), "control: the member was let in"

    following? = Follows.following?(member, group)

    follow_requested? =
      Bonfire.Social.Requests.requested?(member, :follow, group)
      |> debug("follow still requested after the membership was accepted?")

    session =
      conn(user: member, account: account)
      |> visit(Bonfire.Common.URIs.path(group))
      |> wait_async()

    cond do
      following? ->
        session
        |> assert_has_or_open_browser(@round_following)
        |> click_button(@round_following, "")
        |> refute_has("*", text: "error")

      follow_requested? ->
        # a pending request shows as one (`data-id=unfollow`, "Cancel follow request"), never as a plain Follow, whose click would ask again
        session
        |> assert_has_or_open_browser("[data-id=unfollow][aria-label='Cancel follow request']")
        |> refute_has(@round_not_following)

      true ->
        session
        |> assert_has_or_open_browser(@round_not_following)
        |> click_button(@round_not_following, "")
        |> refute_has("*", text: "error")

        assert Follows.following?(member, group), "the click followed the group"
    end
  end

  # the group's CREATOR is a member from creation, not through `join_and_follow_group/2`
  test "the group's creator sees its round Follow as it is, and clicking it gives no error",
       context do
    creator_account = fake_account!()
    creator = fake_user!(creator_account)

    group =
      Bonfire.Classify.Simulate.fake_group!(creator, %{
        name: "My own club",
        membership: "open",
        visibility: "global",
        participation: "anyone",
        default_content_visibility: "public"
      })

    assert Categories.member?(creator, group), "control: the creator is a member"
    following? = Follows.following?(creator, group)

    session =
      conn(user: creator, account: creator_account)
      |> visit(Bonfire.Common.URIs.path(group))
      |> wait_async()

    if following? do
      session
      |> assert_has_or_open_browser(@round_following)
      |> click_button(@round_following, "")
      |> refute_has("*", text: "error")

      refute Follows.following?(creator, group)
    else
      session
      |> assert_has_or_open_browser(@round_not_following)
      |> click_button(@round_not_following, "")
      |> refute_has("*", text: "error")

      assert Follows.following?(creator, group), "the click followed the group"
    end
  end
end
