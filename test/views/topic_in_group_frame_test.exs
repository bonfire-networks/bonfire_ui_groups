defmodule Bonfire.UI.Groups.TopicInGroupFrameTest do
  @moduledoc """
  A topic inside a group keeps its own URL (`/<group>/topic/<topic>`) but opens inside the group frame: the group header, and the topic chips with that topic selected; the selected chip opens the topic's actions (follow, notifications, settings), so there's no separate topic header. The chips switch by live patch within `GroupLive`, so only what is under them changes, and they behave like a filter on the group.

  `/+<topic>` (`CategoryLive`) for a topic that belongs to a group redirects to the in-group URL, so a topic has one page. A top-level topic, with no group, keeps the full topic header.
  """
  use Bonfire.UI.Groups.ConnCase, async: false
  @moduletag :ui

  alias Bonfire.Classify.Simulate

  @current_chip "[data-id=group_topics] [data-role=group-topic-current]"
  @topic_menu "[data-id=group_topics] [id^=group-topic-menu-][id$=_panel]"

  doctest Bonfire.UI.Groups.GroupLive, only: [group_settings?: 2]

  setup do
    Process.put(:federating, false)
    account = fake_account!()
    creator = fake_user!(account)

    group =
      Simulate.fake_group!(creator, %{
        name: "Reading together",
        membership: "open",
        visibility: "global"
      })

    topic =
      Simulate.fake_category!(creator, group, %{
        name: "Reading notes",
        type: :topic,
        summary: "Passages worth discussing."
      })

    sibling = Simulate.fake_category!(creator, group, %{name: "Book club", type: :topic})

    %{account: account, creator: creator, group: group, topic: topic, sibling: sibling}
  end

  defp group_path(group), do: Bonfire.Common.URIs.path(group)

  defp topic_path(group, topic),
    do: group_path(group) <> "/topic/" <> topic.character.username

  defp as_creator(ctx), do: conn(user: ctx.creator, account: ctx.account)

  describe "the frame" do
    test "a topic opens inside the group frame, with its chip selected", ctx do
      as_creator(ctx)
      |> visit(topic_path(ctx.group, ctx.topic))
      |> assert_has("[data-id=group_hero] h1", text: "Reading together")
      |> assert_has("#{@current_chip}[aria-current=page]", text: "Reading notes")
      |> refute_has("[data-id=group_topics] #group-topic-all[aria-current=page]")
      # and its sibling topics
      |> assert_has("[data-id=group_topics] #group-topic-link-#{id(ctx.sibling)}",
        text: "Book club"
      )
    end

    test "the selected chip names the topic and opens its follow action, with no separate topic header",
         ctx do
      as_creator(ctx)
      |> visit(topic_path(ctx.group, ctx.topic))
      |> assert_has("#{@current_chip}[aria-current=page]", text: "Reading notes")
      |> assert_has("#{@topic_menu} [data-id=unfollow]", text: "Unfollow topic")
      |> refute_has("[data-id=topic_subheader]")
      |> refute_has("#topic-parent-banner")
    end

    test "moderators get the topic's settings in the chip menu; members don't", ctx do
      as_creator(ctx)
      |> visit(topic_path(ctx.group, ctx.topic))
      |> assert_has("#{@topic_menu} [aria-label='Edit topic']")

      member_account = fake_account!()
      member = fake_user!(member_account)
      {:ok, _} = Bonfire.Classify.Categories.join_group(member, ctx.group)

      conn(user: member, account: member_account)
      |> visit(topic_path(ctx.group, ctx.topic))
      |> assert_has(@current_chip, text: "Reading notes")
      |> refute_has("#{@topic_menu} [aria-label='Edit topic']")
    end
  end

  describe "switching" do
    test "a topic chip patches to the topic's in-group URL, keeping the page", ctx do
      {:ok, view, _html} = live(as_creator(ctx), group_path(ctx.group))

      view
      |> element("#group-topic-link-#{id(ctx.topic)}")
      |> render_click()

      assert assert_patch(view) =~ topic_path(ctx.group, ctx.topic)
      assert has_element?(view, "#{@current_chip}[aria-current=page]", "Reading notes")
      assert has_element?(view, "[data-id=group_hero]")
    end

    # the tests above only check the URL and the chip; this one checks the feed under them follows
    test "a topic chip filters the feed to that topic's posts", ctx do
      Simulate.fake_post_in_topic!(ctx.creator, ctx.topic, "<p>topic entry</p>")
      Simulate.fake_post_in_topic!(ctx.creator, ctx.sibling, "<p>sibling entry</p>")
      Simulate.fake_post_in_group!(ctx.creator, ctx.group, "<p>group entry</p>")

      as_creator(ctx)
      |> visit(group_path(ctx.group))
      |> wait_async()
      |> assert_has("[data-id=feed]", text: "sibling entry")
      |> click_link("#group-topic-link-#{id(ctx.topic)}", "Reading notes")
      |> wait_async()
      |> assert_has("[data-id=feed]", text: "topic entry")
      |> refute_has("[data-id=feed]", text: "sibling entry")
      |> refute_has("[data-id=feed]", text: "group entry")
    end

    test "opening a topic's in-group URL shows only that topic's posts", ctx do
      Simulate.fake_post_in_topic!(ctx.creator, ctx.topic, "<p>topic entry</p>")
      Simulate.fake_post_in_topic!(ctx.creator, ctx.sibling, "<p>sibling entry</p>")

      as_creator(ctx)
      |> visit(topic_path(ctx.group, ctx.topic))
      |> wait_async()
      |> assert_has("[data-id=feed]", text: "topic entry")
      |> refute_has("[data-id=feed]", text: "sibling entry")
    end

    test "a sibling's chip patches from one topic to the other", ctx do
      {:ok, view, _html} = live(as_creator(ctx), topic_path(ctx.group, ctx.topic))

      view
      |> element("#group-topic-link-#{id(ctx.sibling)}")
      |> render_click()

      assert assert_patch(view) =~ topic_path(ctx.group, ctx.sibling)
      assert has_element?(view, "#{@current_chip}[aria-current=page]", "Book club")
    end

    test "All patches back to the group", ctx do
      {:ok, view, _html} = live(as_creator(ctx), topic_path(ctx.group, ctx.topic))

      view
      |> element("#group-topic-all")
      |> render_click()

      assert assert_patch(view) =~ group_path(ctx.group)
      assert has_element?(view, "#group-topic-all[aria-current=page]")
      refute has_element?(view, "[data-id=topic_subheader]")
    end

    # a patch can name a topic this viewer can't load: a stale link, Back to a topic since removed or renamed
    test "patching to a topic that can't be loaded keeps the group page", ctx do
      {:ok, view, _html} = live(as_creator(ctx), group_path(ctx.group))

      render_patch(view, group_path(ctx.group) <> "/topic/no_such_topic")

      assert Process.alive?(view.pid)
      # the test's own patch first, then the page's patch back
      assert_patch(view, group_path(ctx.group) <> "/topic/no_such_topic")
      assert URI.parse(assert_patch(view)).path == group_path(ctx.group)
      assert render(view) =~ "That topic isn&#39;t available."
      assert has_element?(view, "[data-id=group_hero] h1", "Reading together")
      assert has_element?(view, "#group-topic-all[aria-current=page]")
    end
  end

  describe "one page per topic" do
    test "/+topic for a topic in a group redirects to the in-group URL", ctx do
      as_creator(ctx)
      |> visit("/+#{ctx.topic.character.username}")
      |> assert_path(topic_path(ctx.group, ctx.topic))
    end

    # the remote-follow flow and the tab routes have no in-group equivalent, so they stay on the topic's own page
    test "/+topic/interact/follow is not redirected", ctx do
      path = "/+#{ctx.topic.character.username}/interact/follow"

      as_creator(ctx)
      |> visit(path)
      |> assert_path(path)
    end

    test "/topic/<id>/<tab> is not redirected", ctx do
      path = "/topic/#{id(ctx.topic)}/followers"

      as_creator(ctx)
      |> visit(path)
      |> assert_path(path)
    end

    test "a top-level topic keeps the full topic header", ctx do
      standalone = Simulate.fake_category!(ctx.creator, nil, %{name: "Standalone topic"})

      as_creator(ctx)
      |> visit("/+#{standalone.character.username}")
      |> assert_has("[data-id=topic_subheader]", text: "Standalone topic")
      |> refute_has("[data-id=topic_subheader][data-variant=compact]")
      |> refute_has("[data-id=group_hero]")
    end
  end
end
