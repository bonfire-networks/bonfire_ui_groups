defmodule Bonfire.UI.Groups.GroupFeedLoadMoreTest do
  @moduledoc """
  UI-level regression tests for group/topic feed pagination scoping.

  `bonfire_classify/test/topics/topics_test.exs` already verifies at the
  FeedLoader level that page 2+ of a topic feed contains only the topic's
  own posts. This file mirrors that coverage one layer up — through the
  LiveView flow — so that bugs which only manifest in the UI path (such as
  the `context="show_older"` misroute fixed alongside this file) cannot
  silently regress.
  """
  use Bonfire.UI.Groups.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  use Bonfire.Common.Config
  alias Bonfire.Common.DatesTimes
  alias Bonfire.Posts
  alias Bonfire.Classify.Simulate
  alias Bonfire.Social.Boosts
  alias Bonfire.Social.FeedLoader

  setup do
    original_deferred = Config.get([Bonfire.Social.Feeds, :query_with_deferred_join])
    Config.put([Bonfire.Social.Feeds, :query_with_deferred_join], false)

    on_exit(fn ->
      Config.put([Bonfire.Social.Feeds, :query_with_deferred_join], original_deferred)
    end)

    repo().delete_all(Bonfire.Data.Social.FeedPublish)

    account = fake_account!()
    me = fake_user!(account)
    %{account: account, me: me}
  end

  describe "Group page Load more" do
    test "continues from the recent window into older discussions with deferred joins", %{
      account: account,
      me: me
    } do
      Process.put(
        Config.keys_tree([Bonfire.Social.Feeds, :query_with_deferred_join]),
        true
      )

      Process.put(
        Config.keys_tree([Bonfire.UI.Social.FeedLive, :time_limit]),
        7
      )

      group = Simulate.fake_group!(me, %{name: "Older Discussions Group"})

      {old_discussion, old_activity_id} =
        fake_post_in_group_days_ago!(
          me,
          group,
          30,
          "<p>discussion from thirty days ago</p>"
        )

      Simulate.fake_post_in_group!(me, group, "<p>discussion from today</p>")

      recent_discussions =
        FeedLoader.feed(
          :recent_discussions,
          %{feed_ids: [group.character.outbox_id], time_limit: 7},
          current_user: me
        )

      refute FeedLoader.feed_contains?(recent_discussions, old_discussion, current_user: me)

      all_time_discussions =
        FeedLoader.feed(
          :recent_discussions,
          %{feed_ids: [group.character.outbox_id], time_limit: 0},
          current_user: me,
          paginate: [after: recent_discussions.page_info.end_cursor]
        )

      assert FeedLoader.feed_contains?(all_time_discussions, old_discussion, current_user: me)

      conn(user: me, account: account)
      |> visit("/&#{group.character.username}/discussions?time_limit=7")
      |> wait_async()
      |> assert_has_or_open_browser("[data-id=feed] article", text: "discussion from today")
      |> refute_has_or_open_browser("[data-id=feed] article", text: "discussion from thirty days ago")
      |> refute_has("#activity_#{old_activity_id}")
      |> click_link("a[data-id=next_page]", "Next page")
      |> wait_async()
      |> assert_has("#load_more_show_older[data-id=load_more]", text: "Show older activities")
      |> click_button("#load_more_show_older[data-id=load_more]", "Show older activities")
      |> wait_async()
      |> assert_has_or_open_browser("#activity_#{old_activity_id}")
    end

    test "clicking Load more keeps the feed scoped to the group's outbox", %{
      account: account,
      me: me
    } do
      limit = Bonfire.Common.Config.get(:default_pagination_limit, 2)
      total_posts = limit * 3

      group = Simulate.fake_group!(me, %{name: "Paginated Group"})

      # Post in the group (interleave with foreign posts so pagination
      # cursors land in mixed ULID windows — same setup pattern as
      # topics_test.exs:198).
      for n <- 1..total_posts do
        Simulate.fake_post_in_group!(me, group, "<p>group entry #{n}</p>")

        {:ok, _} =
          Posts.publish(
            current_user: me,
            post_attrs: %{post_content: %{html_body: "<p>foreign entry #{n}</p>"}},
            boundary: "public"
          )
      end

      conn = conn(user: me, account: account)

      conn
      |> visit("/&#{group.character.username}")
      |> wait_async()
      |> assert_has("[data-id=feed] article", count: limit)
      |> assert_has_or_open_browser("[data-id=feed]", text: "group entry")
      |> refute_has_or_open_browser("[data-id=feed]", text: "foreign entry")
      |> click_button("[data-id=load_more]", "Load more")
      |> wait_async()
      |> refute_has_or_open_browser("[data-id=feed]", text: "foreign entry")
    end
  end

  describe "Topic page Load more" do
    test "clicking Load more on a topic keeps the feed scoped to the topic's outbox", %{
      account: account,
      me: me
    } do
      limit = Bonfire.Common.Config.get(:default_pagination_limit, 2)
      total_posts = limit * 3

      group = Simulate.fake_group!(me, %{name: "Parent Group"})
      topic = Simulate.fake_category!(me, group, %{type: :topic, name: "Planning"})
      sibling = Simulate.fake_category!(me, group, %{type: :topic, name: "Random"})

      # Posts in the topic, the sibling topic, and the parent group — only
      # the topic's own posts should appear when visiting the topic page.
      for n <- 1..total_posts do
        Simulate.fake_post_in_topic!(me, topic, "<p>topic entry #{n}</p>")
        Simulate.fake_post_in_topic!(me, sibling, "<p>sibling entry #{n}</p>")
        Simulate.fake_post_in_group!(me, group, "<p>group entry #{n}</p>")
      end

      conn = conn(user: me, account: account)

      conn
      |> visit("/&#{topic.character.username}")
      |> wait_async()
      |> assert_has_or_open_browser("[data-id=feed] article", count: limit)
      |> assert_has("[data-id=feed]", text: "topic entry")
      |> refute_has("[data-id=feed]", text: "sibling entry")
      |> refute_has("[data-id=feed]", text: "group entry")
      |> click_button("[data-id=load_more]", "Load more")
      |> wait_async()
      |> refute_has("[data-id=feed]", text: "sibling entry")
      |> refute_has("[data-id=feed]", text: "group entry")
    end
  end

  defp fake_post_in_group_days_ago!(user, group, days, html) do
    boundaries = List.wrap(Bonfire.Classify.Boundaries.read_default_content_visibility(group))
    historical_date = DatesTimes.past(days, :day)
    post_id = DatesTimes.generate_ulid(historical_date)
    group_activity_id = DatesTimes.generate_ulid(historical_date)

    {:ok, post} =
      Posts.publish(
        post_id: post_id,
        current_user: user,
        post_attrs: %{
          post_content: %{html_body: html}
        },
        context_id: group.id,
        to_circles: Bonfire.Classify.Boundaries.post_circles_for_group(group),
        to_boundaries: boundaries
      )

    {:ok, _deleted} = Boosts.unboost(group, post)

    {:ok, _boost} =
      Boosts.boost(group, post,
        pointer_id: group_activity_id,
        notify_creator: false,
        skip_federation: true,
        skip_live_push: true
      )

    {post, group_activity_id}
  end
end
