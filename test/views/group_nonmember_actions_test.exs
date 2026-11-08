defmodule Bonfire.UI.Groups.GroupNonmemberActionsTest do
  @moduledoc "In a group where only members may post and interact, the reply and like controls on its posts follow the same permission the server enforces: a member gets them, a non-member doesn't."
  use Bonfire.UI.Groups.ConnCase, async: false
  @moduletag :ui

  alias Bonfire.Classify.Categories
  alias Bonfire.Social.Likes

  setup do
    Process.put(:federating, false)
    Process.put([:bonfire, :feed_live_update_many_preload_mode], :inline)

    account = fake_account!()
    owner = fake_user!(account)

    # Join "On request", See "Public (federated)", Post "Group members only", New posts "Group members only"
    group =
      Bonfire.Classify.Simulate.fake_group!(owner, %{
        name: "Living lab",
        membership: "on_request",
        visibility: "global",
        participation: "group_members",
        default_content_visibility: "members:private"
      })

    member_account = fake_account!()
    member = fake_user!(member_account)
    {:ok, %{requested: true}} = Categories.join_and_follow_group(member, group)

    {:ok, request} =
      Bonfire.Social.Requests.get(member, Bonfire.Boundaries.Verbs.get_id!(:join), group,
        current_user: owner
      )

    {:ok, _} = Categories.accept_join_request(owner, request)

    nonmember_account = fake_account!()
    nonmember = fake_user!(nonmember_account)

    %{
      owner: owner,
      group: group,
      member: member,
      member_account: member_account,
      nonmember: nonmember,
      nonmember_account: nonmember_account
    }
  end

  defp feed_card(post), do: "[data-id=feed] article[data-object_id='#{post.id}']"

  defp post_in_group(ctx, audience),
    do:
      Bonfire.Classify.Simulate.fake_post_in_group!(
        ctx.owner,
        ctx.group,
        "<p>Lab discussion</p>",
        boundary: audience
      )

  # The group feed shows each post as a discussion preview (its reply count, no reply or like button, for anyone), so the buttons are on the post's own page
  describe "in the group feed" do
    test "a member sees a post as a discussion preview, without reply or like buttons", ctx do
      post = post_in_group(ctx, nil)

      conn(user: ctx.member, account: ctx.member_account)
      |> visit("/&#{ctx.group.character.username}")
      |> wait_async()
      |> assert_has(feed_card(post), text: "Lab discussion")
      |> assert_has("#{feed_card(post)} [data-role=discussion_preview_actions]")
      |> refute_has("#{feed_card(post)} [data-role=reply_enabled]")
      |> refute_has("#{feed_card(post)} [data-role=like_enabled]")
    end

    test "a local non-member doesn't see a post with the group's default audience", ctx do
      member_only = post_in_group(ctx, nil)
      public = post_in_group(ctx, "public")

      conn(user: ctx.nonmember, account: ctx.nonmember_account)
      |> visit("/&#{ctx.group.character.username}")
      |> wait_async()
      |> assert_has(feed_card(public), text: "Lab discussion")
      |> refute_has(feed_card(member_only))
      |> refute_has("#{feed_card(public)} [data-role=reply_enabled]")
      |> refute_has("#{feed_card(public)} [data-role=like_enabled]")
    end
  end

  describe "on the post's page" do
    for audience <- [nil, "public"] do
      test "a member sees the reply and like controls and can like, for a post with #{audience || "the group's default"} audience",
           ctx do
        post = post_in_group(ctx, unquote(audience))

        conn(user: ctx.member, account: ctx.member_account)
        |> visit("/post/#{id(post)}")
        |> wait_async()
        |> assert_has("article", text: "Lab discussion")
        |> assert_has("[data-role=reply_enabled]")
        |> refute_has("[data-id='like_action'][aria-pressed]")
        |> click_button("[data-role=like_enabled]", "Like")
        |> assert_has("[data-id='like_action'][aria-pressed]")

        assert Likes.liked?(ctx.member, post)
      end
    end

    test "a local non-member can't open a post with the group's default audience", ctx do
      post = post_in_group(ctx, nil)

      conn(user: ctx.nonmember, account: ctx.nonmember_account)
      |> visit("/post/#{id(post)}")
      |> wait_async()
      |> refute_has("article", text: "Lab discussion")
      |> refute_has("[data-role=reply_enabled]")
      |> refute_has("[data-role=like_enabled]")
    end

    # the post's own audience wins: "Post: Group members only" says who may post into the group, not who may react to a post whose author made it public
    test "a local non-member gets enabled reply and like controls on a public post in the group, and can like",
         ctx do
      post = post_in_group(ctx, "public")

      conn(user: ctx.nonmember, account: ctx.nonmember_account)
      |> visit("/post/#{id(post)}")
      |> wait_async()
      |> assert_has("article", text: "Lab discussion")
      |> assert_has("[data-role=reply_enabled]")
      |> refute_has("[data-id='like_action'][aria-pressed]")
      |> click_button("[data-role=like_enabled]", "Like")
      |> assert_has("[data-id='like_action'][aria-pressed]")

      assert Likes.liked?(ctx.nonmember, post)
    end
  end

  describe "the server" do
    test "allows a member's like and reply on a post with the group's default audience, and refuses a non-member's",
         ctx do
      post = post_in_group(ctx, nil)

      assert Bonfire.Boundaries.can?(ctx.member, :like, post)
      assert Bonfire.Boundaries.can?(ctx.member, :reply, post)
      refute Bonfire.Boundaries.can?(ctx.nonmember, :like, post)
      refute Bonfire.Boundaries.can?(ctx.nonmember, :reply, post)

      assert {:error, _} = Likes.like(ctx.nonmember, post)
      refute Likes.liked?(ctx.nonmember, post)
    end

    test "allows a member's and a non-member's like and reply on a public post in the group",
         ctx do
      post = post_in_group(ctx, "public")

      for user <- [ctx.member, ctx.nonmember] do
        assert Bonfire.Boundaries.can?(user, :like, post)
        assert Bonfire.Boundaries.can?(user, :reply, post)
      end

      assert {:ok, _} = Likes.like(ctx.nonmember, post)

      assert {:ok, _} =
               Bonfire.Posts.publish(
                 current_user: ctx.nonmember,
                 post_attrs: %{
                   post_content: %{html_body: "<p>a non-member's reply</p>"},
                   reply_to_id: id(post)
                 },
                 boundary: "public"
               )
    end
  end
end
