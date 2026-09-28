defmodule Bonfire.UI.Groups.JoinRequestLifecycleTest do
  @moduledoc """
  Whole journeys through a join request, as the requester and a moderator each see them, always checking a FRESH visit afterwards.

  The context tests pass on `Requests.requested?/3`, which skips ignored rows, while the group page read the same rows back without that filter, so a withdrawn or declined request came back as "Cancel request" on the next visit. Only a returning page shows that, which is why each step here re-visits rather than trusting the live update.
  """
  use Bonfire.UI.Groups.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui
  use Bonfire.Common.E

  alias Bonfire.Classify.Simulate
  alias Bonfire.Classify.Categories
  alias Bonfire.Social.Requests

  setup do
    Process.put(:federating, false)

    creator = fake_user!()
    moderator_account = fake_account!()
    moderator = fake_user!(moderator_account)
    requester_account = fake_account!()
    requester = fake_user!(requester_account)

    # the "Private club" preset's slugs: discoverable, so a non-member reaches the page and its Request to join, while only members read it
    group =
      Simulate.fake_group!(creator, %{
        membership: "on_request",
        visibility: "local:preview",
        participation: "group_members",
        default_content_visibility: "members:private"
      })

    {:ok, _} = Categories.add_moderator(creator, group, id(moderator))

    {:ok,
     creator: creator,
     moderator: moderator,
     group: group,
     group_path: "/&#{e(group, :character, :username, nil)}",
     join_btn: "#join_btn_#{group.id}",
     requester: requester,
     as_requester: fn -> conn(user: requester, account: requester_account) end,
     as_moderator: fn -> conn(user: moderator, account: moderator_account) end}
  end

  defp join_request!(requester, group) do
    assert {:ok, request} =
             Requests.get(requester, Bonfire.Boundaries.Verbs.get_id!(:join), group,
               skip_boundary_check: true
             ),
           "control: expected a join request row"

    request
  end

  defp request_button(request_id), do: "[data-id=feed] article button[phx-value-id='#{request_id}']"

  defp visit_fresh(conn, path), do: conn |> visit(path) |> wait_async()

  test "request → withdraw → fresh visit shows Request to join → request again reaches the moderators",
       ctx do
    ctx.as_requester.()
    |> visit_fresh(ctx.group_path)
    |> assert_has("#group_access_gate")
    |> click_button(ctx.join_btn, "Request to join")
    |> assert_has(ctx.join_btn, text: "Cancel request")

    withdrawn = join_request!(ctx.requester, ctx.group)

    ctx.as_requester.()
    |> visit_fresh(ctx.group_path)
    |> assert_has(ctx.join_btn, text: "Cancel request")
    |> click_button(ctx.join_btn, "Cancel request")
    |> refute_has("[data-id=flash_error]")
    |> assert_has(ctx.join_btn, text: "Request to join")

    # BF01: this is where the withdrawn request used to come back as pending
    ctx.as_requester.()
    |> visit_fresh(ctx.group_path)
    |> assert_has(ctx.join_btn, text: "Request to join")
    |> refute_has(ctx.join_btn, text: "Cancel request")
    |> assert_has("#group_access_gate")

    ctx.as_moderator.()
    |> visit_fresh("/notifications")
    |> refute_has(request_button(withdrawn.id))

    ctx.as_requester.()
    |> visit_fresh(ctx.group_path)
    |> click_button(ctx.join_btn, "Request to join")
    |> assert_has(ctx.join_btn, text: "Cancel request")

    ctx.as_requester.()
    |> visit_fresh(ctx.group_path)
    |> assert_has(ctx.join_btn, text: "Cancel request")
    |> assert_has("#group_access_gate")

    asked_again = join_request!(ctx.requester, ctx.group)
    assert asked_again.id != withdrawn.id

    ctx.as_moderator.()
    |> visit_fresh("/notifications")
    |> assert_has(request_button(asked_again.id), text: "Accept")
  end

  test "request → Ignore → fresh visit shows Request to join → request again → moderator approves → requester has member access",
       ctx do
    group_name = e(ctx.group, :profile, :name, nil)

    ctx.as_requester.()
    |> visit_fresh(ctx.group_path)
    |> click_button(ctx.join_btn, "Request to join")
    |> assert_has(ctx.join_btn, text: "Cancel request")

    declined = join_request!(ctx.requester, ctx.group)

    ctx.as_moderator.()
    |> visit_fresh("/notifications")
    |> click_button(request_button(declined.id), "Ignore")
    |> refute_has("[data-id=flash_error]")

    # a decline is silent: nothing about the group lands in the requester's notifications
    ctx.as_requester.()
    |> visit_fresh("/notifications")
    |> refute_has("[data-id=feed] article", text: group_name)

    # BF11: the declined request used to come back as "Cancel request", with no way to ask again
    ctx.as_requester.()
    |> visit_fresh(ctx.group_path)
    |> assert_has(ctx.join_btn, text: "Request to join")
    |> refute_has(ctx.join_btn, text: "Cancel request")
    |> assert_has("#group_access_gate")
    |> click_button(ctx.join_btn, "Request to join")
    |> assert_has(ctx.join_btn, text: "Cancel request")

    asked_again = join_request!(ctx.requester, ctx.group)
    assert asked_again.id != declined.id, "asking again is a new attempt, not the declined one revived"

    ctx.as_moderator.()
    |> visit_fresh("/notifications")
    |> refute_has(request_button(declined.id))
    |> click_button(request_button(asked_again.id), "Accept")
    |> refute_has("[data-id=flash_error]")

    assert Categories.member?(ctx.requester, ctx.group)

    ctx.as_requester.()
    |> visit_fresh(ctx.group_path)
    |> assert_has(ctx.join_btn, text: "Joined")
    |> refute_has("#group_access_gate")
    |> assert_has("#inline_composer_placeholder_open", text: "Write in")
  end

  # The live row removal after Accept is covered (and currently red for a LiveViewTest reason) in `join_request_notification_test.exs`; this checks what a moderator finds when they come back, tied to the request that was accepted.
  test "after accepting, a fresh visit offers no Accept, and both halves of pressing Join are settled",
       ctx do
    # members-private rather than the club: it grants non-members no `:follow`, so pressing Join leaves a follow request beside the join request, and the accept has to settle both
    group =
      Simulate.fake_group!(ctx.creator, %{
        membership: "on_request",
        visibility: "members:private",
        participation: "group_members",
        default_content_visibility: "members:private"
      })

    {:ok, _} = Categories.add_moderator(ctx.creator, group, id(ctx.moderator))

    {:ok, %{requested: true}} = Categories.join_and_follow_group(ctx.requester, group)
    join_request = join_request!(ctx.requester, group)

    assert {:ok, follow_request} =
             Requests.get(ctx.requester, Bonfire.Data.Social.Follow, group,
               skip_boundary_check: true
             ),
           "control: this group grants non-members no :follow, so pressing Join also left a follow request"

    ctx.as_moderator.()
    |> visit_fresh("/notifications")
    |> click_button(request_button(join_request.id), "Accept")
    |> refute_has("[data-id=flash_error]")

    ctx.as_moderator.()
    |> visit_fresh("/notifications")
    |> refute_has(request_button(join_request.id))
    |> refute_has(request_button(follow_request.id))
    |> refute_has("[data-id=feed] article button", text: "Accept")

    assert is_nil(Requests.edge(join_request.id)), "the accepted join request is consumed"
    assert is_nil(Requests.edge(follow_request.id)), "the follow half is settled with it"
    assert Categories.member?(ctx.requester, group)
    assert Bonfire.Social.Graph.Follows.following?(ctx.requester, group)
  end
end
