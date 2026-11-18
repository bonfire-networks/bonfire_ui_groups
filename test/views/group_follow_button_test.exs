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
  # the same button for someone who has not joined (a guest, or a signed-in non-member): the hero words it "Follow without joining" there, since Join is the other button beside it
  @visitor_round_follow "[data-id=follow][data-tip='Follow without joining']"

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

  # A guest has no account here, so following or joining is a remote interaction: they enter their own fediverse handle and act from their instance. Sending them to log in instead is a dead end
  describe "a guest on a local group" do
    @remote_interaction "Are you a fediverse user?"

    test "the round Follow leads to remote interaction, not to the login page", context do
      conn()
      |> visit(Bonfire.Common.URIs.path(context.group))
      |> wait_async()
      |> click_link("a#{@visitor_round_follow}", "")
      |> refute_path("/login")
      |> assert_has("*", text: @remote_interaction)
    end

    test "Join leads to remote interaction, not to the login page", context do
      conn()
      |> visit(Bonfire.Common.URIs.path(context.group))
      |> wait_async()
      # by id: `:on-click` renders `phx-click` as a JS push command, not the event's name
      |> click_button(
        "button#{component_selector(Bonfire.Classify.Web.JoinButtonLive, id(context.group))}",
        "Join"
      )
      |> refute_path("/login")
      |> assert_has("*", text: @remote_interaction)
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

  # an open group hosted elsewhere (Mbin, Lemmy) admits at once, while the Follow sent alongside waits for its answer
  test "Join on an open group hosted elsewhere waits for its answer, then shows us as a member while the follow waits",
       context do
    account = fake_account!()
    joiner = fake_user!(account)

    mirrored =
      Bonfire.Classify.Simulate.fake_group!(context.member, %{
        name: "Open elsewhere",
        membership: "open",
        visibility: "global",
        participation: "anyone",
        default_content_visibility: "public"
      })

    assert {:ok, _} =
             Bonfire.Federate.ActivityPub.Peered.save_canonical_uri(
               mirrored,
               "https://elsewhere.local/m/open"
             )

    conn = conn(user: joiner, account: account)

    # a Join on a group hosted elsewhere waits for the group's own answer, even when it is open
    conn
    |> visit(Bonfire.Common.URIs.path(mirrored))
    |> wait_async()
    |> click_button(component_selector(Bonfire.Classify.Web.JoinButtonLive, mirrored.id), "Join")
    # |> assert_has("[data-id=group_hero][data-variant=member]")
    |> assert_has("button", text: "Joining…")
    |> refute_has("[data-id=group_hero][data-variant=member]")

    refute Categories.member?(joiner, mirrored), "control: the group has not answered the Join"

    # the group answers the Join as its Accept would, leaving the Follow sent alongside still waiting
    assert {:ok, _} =
             Categories.join_group(joiner, mirrored, skip_boundary_check: true, incoming: true)

    # the follow waiting must not stop the header showing the membership
    conn
    |> visit(Bonfire.Common.URIs.path(mirrored))
    |> wait_async()
    |> assert_has("[data-id=group_hero][data-variant=member]")

    assert Categories.member?(joiner, mirrored)

    assert Bonfire.Social.Requests.requested?(joiner, Bonfire.Data.Social.Follow, mirrored),
           "control: the follow of a group hosted elsewhere waits for its answer"
  end

  # Following a group does not follow its topics, so after the group's own Follow a modal offers them, none ticked. The group's Follow takes effect first: the modal is an optional extra.
  describe "the topics modal after Follow" do
    @picker "[data-role=group_topics_picker]"
    @picker_submit "[data-role=group_topics_picker_submit]"

    setup do
      owner = fake_user!()
      account = fake_account!()
      visitor = fake_user!(account)

      group =
        Bonfire.Classify.Simulate.fake_group!(owner, %{
          name: "Topical club",
          membership: "open",
          visibility: "global",
          participation: "anyone",
          default_content_visibility: "public"
        })

      %{owner: owner, visitor: visitor, account: account, group: group}
    end

    test "a group with no topics shows no modal, and Follow still follows it", ctx do
      conn(user: ctx.visitor, account: ctx.account)
      |> visit(Bonfire.Common.URIs.path(ctx.group))
      |> wait_async()
      |> click_button(@visitor_round_follow, "")
      |> wait_async()
      |> refute_has(@picker)

      assert Follows.following?(ctx.visitor, ctx.group),
             "control: the group's own Follow took effect"
    end

    test "ticking one topic follows only that topic", ctx do
      t1 =
        Bonfire.Classify.Simulate.fake_category!(ctx.owner, ctx.group, %{
          name: "Seed swap",
          type: :topic
        })

      t2 =
        Bonfire.Classify.Simulate.fake_category!(ctx.owner, ctx.group, %{
          name: "Tool library",
          type: :topic
        })

      conn(user: ctx.visitor, account: ctx.account)
      |> visit(Bonfire.Common.URIs.path(ctx.group))
      |> wait_async()
      |> click_button(@visitor_round_follow, "")
      |> assert_has(@picker, text: "Seed swap")
      |> assert_has(@picker, text: "Tool library")
      # none ticked to start with
      |> refute_has("#{@picker} input[type=checkbox][checked]")
      |> check("Seed swap")
      |> click_button(@picker_submit, "Follow")

      assert Follows.following?(ctx.visitor, ctx.group), "the group's own Follow stands"
      assert Follows.following?(ctx.visitor, t1)
      refute Follows.following?(ctx.visitor, t2)
    end

    # a topic already followed is not a locked checkbox but the follow button in its following state, which unfollows it from the modal without opening another modal
    test "an already followed topic shows the follow button, and unfollowing it opens nothing",
         ctx do
      t1 =
        Bonfire.Classify.Simulate.fake_category!(ctx.owner, ctx.group, %{
          name: "Seed swap",
          type: :topic
        })

      t2 =
        Bonfire.Classify.Simulate.fake_category!(ctx.owner, ctx.group, %{
          name: "Tool library",
          type: :topic
        })

      assert {:ok, _} = Follows.follow(ctx.visitor, t1)

      session =
        conn(user: ctx.visitor, account: ctx.account)
        |> visit(Bonfire.Common.URIs.path(ctx.group))
        |> wait_async()
        |> click_button(@visitor_round_follow, "")
        |> assert_has("#{@picker} [data-topic-id='#{id(t1)}'] [data-id=unfollow]")
        |> refute_has("#{@picker} input[type=checkbox][disabled]")
        |> assert_has("#{@picker} input[type=checkbox][value='#{id(t2)}']")
        |> refute_has("#{@picker} input[type=checkbox][value='#{id(t1)}']")
        |> click_button("#{@picker} [data-topic-id='#{id(t1)}'] [data-id=unfollow]", "")

      refute Follows.following?(ctx.visitor, t1)

      # still the one modal, not a second one for the topic
      session |> assert_has(@picker)
    end

    # the same modal on Unfollow, listing the topics you follow so you can stop those too
    test "unfollowing the group offers the topics you follow, to stop those too", ctx do
      t1 =
        Bonfire.Classify.Simulate.fake_category!(ctx.owner, ctx.group, %{
          name: "Seed swap",
          type: :topic
        })

      _t2 =
        Bonfire.Classify.Simulate.fake_category!(ctx.owner, ctx.group, %{
          name: "Tool library",
          type: :topic
        })

      assert {:ok, _} = Follows.follow(ctx.visitor, ctx.group)
      assert {:ok, _} = Follows.follow(ctx.visitor, t1)

      conn(user: ctx.visitor, account: ctx.account)
      |> visit(Bonfire.Common.URIs.path(ctx.group))
      |> wait_async()
      |> click_button(@round_following, "")
      |> assert_has(@picker, text: "Seed swap")
      |> refute_has(@picker, text: "Tool library")

      refute Follows.following?(ctx.visitor, ctx.group),
             "control: the group's own Unfollow took effect"
    end

    # a group hosted elsewhere: our Follow waits for its answer, and the button reads "Requested" (its click withdraws the request)
    defp mirror!(object, uri) do
      assert {:ok, _} = Bonfire.Federate.ActivityPub.Peered.save_canonical_uri(object, uri)
      object
    end

    @pending_group_button "button[data-id=unfollow][aria-label='Cancel follow request']"

    test "withdrawing a pending Follow of a group hosted elsewhere offers the topics you follow",
         ctx do
      group = mirror!(ctx.group, "https://elsewhere.local/m/topical")

      t1 =
        Bonfire.Classify.Simulate.fake_category!(ctx.owner, group, %{
          name: "Seed swap",
          type: :topic
        })

      assert {:ok, _} = Follows.follow(ctx.visitor, group)
      assert {:ok, _} = Follows.follow(ctx.visitor, t1)

      assert Bonfire.Social.Requests.requested?(ctx.visitor, :follow, group),
             "control: the group's Follow is still a pending request"

      conn(user: ctx.visitor, account: ctx.account)
      |> visit(Bonfire.Common.URIs.path(group))
      |> wait_async()
      |> assert_has_or_open_browser(@pending_group_button)
      |> click_button(@pending_group_button, "")
      |> assert_has(@picker, text: "Seed swap")

      refute Bonfire.Social.Requests.requested?(ctx.visitor, :follow, group),
             "control: the click withdrew the request"
    end

    test "unfollowing a group offers the topics whose Follow is still a pending request", ctx do
      group = ctx.group

      t1 =
        Bonfire.Classify.Simulate.fake_category!(ctx.owner, group, %{
          name: "Seed swap",
          type: :topic
        })

      mirror!(t1, "https://elsewhere.local/m/topical/seed-swap")

      assert {:ok, _} = Follows.follow(ctx.visitor, group)
      assert {:ok, _} = Follows.follow(ctx.visitor, t1)

      assert Bonfire.Social.Requests.requested?(ctx.visitor, :follow, t1),
             "control: the topic's Follow is a pending request"

      conn(user: ctx.visitor, account: ctx.account)
      |> visit(Bonfire.Common.URIs.path(group))
      |> wait_async()
      |> click_button(@round_following, "")
      |> assert_has(@picker, text: "Seed swap")
    end

    test "ticking every topic follows them all", ctx do
      t1 =
        Bonfire.Classify.Simulate.fake_category!(ctx.owner, ctx.group, %{
          name: "Seed swap",
          type: :topic
        })

      t2 =
        Bonfire.Classify.Simulate.fake_category!(ctx.owner, ctx.group, %{
          name: "Tool library",
          type: :topic
        })

      conn(user: ctx.visitor, account: ctx.account)
      |> visit(Bonfire.Common.URIs.path(ctx.group))
      |> wait_async()
      |> click_button(@visitor_round_follow, "")
      |> assert_has(@picker)
      # the "all topics" toggle is Alpine, which this driver does not run: it ticks the same boxes
      |> check("Seed swap")
      |> check("Tool library")
      |> click_button(@picker_submit, "Follow")

      assert Follows.following?(ctx.visitor, t1)
      assert Follows.following?(ctx.visitor, t2)
    end
  end
end
