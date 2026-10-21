defmodule Bonfire.UI.Groups.GroupPinsTest do
  @moduledoc "A group's moderators pin posts to the top of the group, or of one of its topics. Pins show in a carousel above the feed, each page only its own scope's, and the post's menu offers pinning to moderators only."
  use Bonfire.UI.Groups.ConnCase, async: false
  @moduletag :ui

  alias Bonfire.Classify.Categories
  alias Bonfire.Classify.Simulate
  alias Bonfire.Social.Pins
  import Bonfire.Posts.Fake, only: [fake_comment!: 2]

  setup do
    Process.put(:federating, false)
    Process.put([:bonfire, :feed_live_update_many_preload_mode], :inline)

    creator = fake_user!(fake_account!())
    moderator_account = fake_account!()
    moderator = fake_user!(moderator_account)
    member_account = fake_account!()
    member = fake_user!(member_account)

    group =
      Simulate.fake_group!(creator, %{
        name: "Pin board",
        membership: "open",
        visibility: "global",
        participation: "group_members"
      })

    {:ok, _} = Categories.join_group(member, id(group))
    {:ok, _} = Categories.add_moderator(creator, group, id(moderator))

    topic = Simulate.fake_category!(creator, group, %{name: "Announcements", type: :topic})

    %{
      creator: creator,
      moderator: moderator,
      moderator_account: moderator_account,
      member: member,
      member_account: member_account,
      group: group,
      topic: topic,
      post: Simulate.fake_post_in_group!(member, group, "<p>Worth pinning</p>"),
      topic_post: Simulate.fake_post_in_topic!(member, topic, "<p>Topic news</p>")
    }
  end

  defp group_path(group), do: Bonfire.Common.URIs.path(group)

  defp topic_path(group, topic),
    do: group_path(group) <> "/topic/" <> topic.character.username

  defp as_moderator(ctx), do: conn(user: ctx.moderator, account: ctx.moderator_account)
  defp as_member(ctx), do: conn(user: ctx.member, account: ctx.member_account)

  # group and topic feed cards have no menu (`DiscussionPreviewActionsLive`), so pinning is offered on the post's own page, beside "Remove from group", for the group or topic the post was published in
  defp open_post_menu(session, post, text) do
    session
    |> visit("/post/#{id(post)}")
    |> wait_async()
    |> assert_has("article", text: text)
    |> open_more_menu()
  end

  describe "the post's menu" do
    test "offers a moderator \"Pin to top of group\" on a group post", ctx do
      as_moderator(ctx)
      |> open_post_menu(ctx.post, "Worth pinning")
      |> assert_has("[data-role=pin_to_group]", text: "Pin to top of group")
      |> refute_has("[data-role=pin_to_topic]")
    end

    test "doesn't offer either to a member", ctx do
      as_member(ctx)
      |> open_post_menu(ctx.topic_post, "Topic news")
      # the control: the menu's permission rows did render, so the rows' absence is the permission
      |> assert_has("[data-id=boundary_details]")
      |> refute_has("[data-role=pin_to_topic]")
      |> refute_has("[data-role=pin_to_group]")
      |> refute_has("[data-role=pin_menu]")
    end

    # the post's page decides its other menu rows from the loaded boundary, before the menu opens; the group and topic rows cost a few queries, so they wait for a moderator to open it
    test "the group and topic rows load when the menu opens, not with the page", ctx do
      as_moderator(ctx)
      |> visit("/post/#{id(ctx.topic_post)}")
      |> assert_has("article", text: "Topic news")
      |> assert_has("[data-id=boundary_details]")
      |> refute_has("[data-role=pin_to_group]")
      |> open_more_menu()
      |> assert_has("[data-role=pin_to_group]")
    end

    # one entry however many places there are to pin to, so the menu doesn't grow a row for each
    test "gathers the places a moderator may pin it under one Pin entry", ctx do
      as_moderator(ctx)
      |> open_post_menu(ctx.topic_post, "Topic news")
      |> assert_has("[data-role=pin_menu] summary", text: "Pin this activity")
      |> assert_has("[data-role=pin_menu] [data-role=pin_to_topic]", text: "Pin to top of topic")
      |> assert_has("[data-role=pin_menu] [data-role=pin_to_group]", text: "Pin to top of group")
    end

    test "an instance admin who moderates the group finds the spotlight in the same entry", ctx do
      admin_account = fake_account!()
      admin = fake_admin!(admin_account)
      {:ok, _} = Categories.add_moderator(ctx.creator, ctx.group, id(admin))

      conn(user: admin, account: admin_account)
      |> open_post_menu(ctx.post, "Worth pinning")
      |> assert_has("[data-role=pin_menu] [data-role=pin_to_group]")
      |> assert_has("[data-role=pin_menu] [data-role=pin_to_instance]", text: "spotlight")
      |> assert_has("[data-role=pin_to_instance]", count: 1)
    end

    test "pinning from it pins to the topic, and the menu then offers to unpin without a reload",
         ctx do
      as_moderator(ctx)
      |> open_post_menu(ctx.topic_post, "Topic news")
      |> click_button("[data-role=pin_to_topic] [data-role=open_modal]", "Pin to top of topic")
      # the modal's content renders outside the menu row
      |> click_button("[data-id=pin_action]", "Pin to top of topic")
      |> assert_has("[data-role=pin_to_topic]", text: "Unpin from top of topic")
      # the other scope's row is untouched
      |> assert_has("[data-role=pin_to_group]", text: "Pin to top of group")

      assert Pins.pinned?(id(ctx.topic), ctx.topic_post)
      refute Pins.pinned?(id(ctx.group), ctx.topic_post)
    end
  end

  describe "the pinned cards" do
    test "sit under a small Pinned label, not a heading", ctx do
      {:ok, _} = Pins.pin(ctx.moderator, ctx.post, id(ctx.group))

      as_member(ctx)
      |> visit(group_path(ctx.group))
      |> assert_has("#group_pinned_carousel [data-role=widget-heading]", text: "Pinned")
      |> refute_has("#group_pinned_carousel", text: "Pinned in this group")
      |> assert_has("#group_pinned_carousel [data-role=pinned_card]", count: 1)
    end

    test "the card previews the post as Top discussions does", ctx do
      {:ok, _} = Pins.pin(ctx.moderator, ctx.post, id(ctx.group))

      as_member(ctx)
      |> visit(group_path(ctx.group))
      |> assert_has("[data-role=pinned_card]", text: "Worth pinning")
      |> assert_has("[data-role=pinned_card] [data-role=discussion_preview_actions]")
    end

    test "the card shows who else is in the thread", ctx do
      replier = fake_user!(fake_account!())

      fake_comment!(replier, ctx.post)

      {:ok, _} = Pins.pin(ctx.moderator, ctx.post, id(ctx.group))

      as_member(ctx)
      |> visit(group_path(ctx.group))
      |> assert_has("[data-role=pinned_card] [data-role=thread_participants]")
    end

    test "one pin shows no dots, two show one dot each", ctx do
      {:ok, _} = Pins.pin(ctx.moderator, ctx.post, id(ctx.group))

      as_member(ctx)
      |> visit(group_path(ctx.group))
      |> refute_has("#group_pinned_carousel [data-role=carousel_dots]")

      another = Simulate.fake_post_in_group!(ctx.member, ctx.group, "<p>Also worth pinning</p>")
      {:ok, _} = Pins.pin(ctx.moderator, another, id(ctx.group))

      as_member(ctx)
      |> visit(group_path(ctx.group))
      |> assert_has("#group_pinned_carousel [data-role=carousel_dots] [data-role=carousel_dot]",
        count: 2
      )
    end

    test "a moderator can unpin from the card, a member gets no such action", ctx do
      {:ok, _} = Pins.pin(ctx.moderator, ctx.post, id(ctx.group))

      as_member(ctx)
      |> visit(group_path(ctx.group))
      |> assert_has("[data-role=pinned_card]")
      |> refute_has("[data-role=pinned_card] [data-role=pin_to_group]")

      as_moderator(ctx)
      |> visit(group_path(ctx.group))
      |> click_button(
        "[data-role=pinned_card] [data-role=pin_to_group] [data-role=open_modal]",
        "Unpin from top of group"
      )
      |> click_button("[data-id=unpin_action]", "Unpin from top of group")
      |> refute_has("#group_pinned_carousel aside")

      refute Pins.pinned?(id(ctx.group), ctx.post)
    end
  end

  # the group feed's cards are the same Top discussions preview, so they get the same facepile
  describe "the group feed" do
    # "who else": the post's author shows on the card itself, as in the spotlight's facepile
    test "a post's facepile leaves out its author", ctx do
      replier = fake_user!(fake_account!())

      fake_comment!(replier, ctx.post)

      facepile = "article[data-object_id='#{id(ctx.post)}'] [data-role=thread_participants]"

      as_member(ctx)
      |> visit(group_path(ctx.group))
      |> assert_has(~s(#{facepile}[title*="#{replier.profile.name}"]))
      |> refute_has(~s(#{facepile}[title*="#{ctx.member.profile.name}"]))
    end
  end

  describe "the carousel" do
    test "pinning shows the post above the feed without a reload, and unpinning removes it", ctx do
      as_moderator(ctx)
      |> visit(group_path(ctx.group))
      |> refute_has("#group_pinned_carousel aside")
      |> PhoenixTest.unwrap(fn view ->
        render_hook(view, "Bonfire.Social.Pins:pin", %{
          "direction" => "up",
          "id" => id(ctx.post),
          "scope" => id(ctx.group)
        })

        assert has_element?(view, "#group_pinned_carousel", "Worth pinning")

        render_hook(view, "Bonfire.Social.Pins:pin", %{
          "direction" => "down",
          "id" => id(ctx.post),
          "scope" => id(ctx.group)
        })

        refute has_element?(view, "#group_pinned_carousel aside")

        render(view)
      end)
    end

    test "a topic's pins show on that topic only, and the group's on the group page only", ctx do
      {:ok, _} = Pins.pin(ctx.moderator, ctx.post, id(ctx.group))
      {:ok, _} = Pins.pin(ctx.moderator, ctx.topic_post, id(ctx.topic))

      as_member(ctx)
      |> visit(group_path(ctx.group))
      |> assert_has("#group_pinned_carousel", text: "Worth pinning")
      |> refute_has("#group_pinned_carousel", text: "Topic news")
      |> visit(topic_path(ctx.group, ctx.topic))
      |> assert_has("#group_pinned_carousel", text: "Topic news")
      |> refute_has("#group_pinned_carousel", text: "Worth pinning")
    end

    # a pinned post also stays in the feed below, so its two renderings must not share DOM ids
    test "a pinned post shown in the carousel and in the feed doesn't repeat DOM ids", ctx do
      {:ok, _} = Pins.pin(ctx.moderator, ctx.post, id(ctx.group))

      as_member(ctx)
      |> visit(group_path(ctx.group))
      |> assert_has("#group_pinned_carousel", text: "Worth pinning")
      |> PhoenixTest.unwrap(fn view ->
        html = render(view)

        duplicates =
          html
          |> Floki.parse_document!()
          |> Floki.attribute("[id]", "id")
          |> Enum.frequencies()
          |> Enum.filter(fn {_id, count} -> count > 1 end)

        assert duplicates == []
        html
      end)
    end
  end

  # another moderator, another tab, an API client or a federated `Add` to the group's `featured`: the open page learns of it from `Pins`, not from the event that made it
  describe "a pin made elsewhere" do
    test "shows on an open group page", ctx do
      session =
        as_member(ctx)
        |> visit(group_path(ctx.group))
        |> refute_has("#group_pinned_carousel [data-role=pinned_card]")

      {:ok, _} = Pins.pin(ctx.moderator, ctx.post, id(ctx.group))

      assert_has(session, "#group_pinned_carousel [data-role=pinned_card]",
        text: "Worth pinning",
        timeout: 1_000
      )
    end

    test "unpinned, leaves an open group page", ctx do
      {:ok, _} = Pins.pin(ctx.moderator, ctx.post, id(ctx.group))

      session =
        as_member(ctx)
        |> visit(group_path(ctx.group))
        |> assert_has("#group_pinned_carousel [data-role=pinned_card]")

      Pins.unpin(ctx.moderator, id(ctx.post), id(ctx.group))

      refute_has(session, "#group_pinned_carousel [data-role=pinned_card]", timeout: 1_000)
    end
  end
end
