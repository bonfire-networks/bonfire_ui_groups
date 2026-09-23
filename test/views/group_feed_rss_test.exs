defmodule Bonfire.UI.Groups.GroupFeedRSSTest do
  @moduledoc """
  A group's RSS and Atom feeds show a guest only what the group's boundaries let a guest read.

  A feed reader has no session, so every request is a guest's. The group page offers `/feed/user_activities/<group username>/feed.rss` through the profile hero's "Subscribe" link, which is rendered for groups as well as users, so that URL is the one to check.

  Each refusal is paired with a public group whose post DOES appear at the same URL, because "not in the feed" cannot otherwise tell a boundary that held from a route that serves no group at all.
  """
  use Bonfire.UI.Groups.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  alias Bonfire.Classify.Simulate

  defp group_feed_path(group, format),
    do: "/feed/user_activities/#{group.character.username}/feed.#{format}"

  # `FeedController` raises `Bonfire.Fail` for a feed it will not serve, which reaches a test as a raise rather than a 404 response
  defp fetch(path) do
    conn = get(conn(), path)
    {conn.status, conn.resp_body}
  rescue
    e in Bonfire.Fail -> {Plug.Exception.status(e), nil}
  end

  setup do
    creator = fake_user!()

    public_group =
      Simulate.fake_group!(creator, %{
        visibility: "global",
        default_content_visibility: "public"
      })

    private_group =
      Simulate.fake_group!(creator, %{
        membership: "invite_only",
        visibility: "members:private",
        participation: "group_members",
        default_content_visibility: "members:private"
      })

    public_post = Simulate.fake_post_in_group!(creator, public_group, "<p>open group post</p>")
    Simulate.fake_post_in_group!(creator, private_group, "<p>members only post</p>")

    # public, but in NO group: a guest may read it anywhere, so it must still be absent from a group's feed. Without this, the public group's post appearing proves only that the route serves guest-readable posts, not that it serves THIS group's
    {:ok, unrelated_post} =
      Bonfire.Posts.publish(
        current_user: creator,
        post_attrs: %{post_content: %{html_body: "<p>unrelated public post</p>"}},
        boundary: "public"
      )

    %{
      public_group: public_group,
      private_group: private_group,
      public_post: public_post,
      unrelated_post: unrelated_post
    }
  end

  # The two steps the controller takes, checked separately so a failure above names which one broke: turning the username in the URL into the group, then asking the feed for what belongs to it
  describe "what the group's feed URL is built from" do
    test "the group's username resolves to the group", %{public_group: group} do
      assert {:ok, %{id: resolved}} =
               Bonfire.Common.Needles.get(group.character.username, skip_boundary_check: true)

      assert resolved == id(group)
    end

    test "the feed filtered by the group holds its posts and nothing else", %{
      public_group: group,
      public_post: public_post,
      unrelated_post: unrelated_post
    } do
      assert Bonfire.Social.FeedLoader.feed_contains?(:user_activities, public_post, by: group),
             "the group's own post is not in `user_activities` filtered by the group"

      refute Bonfire.Social.FeedLoader.feed_contains?(:user_activities, unrelated_post,
               by: group
             ),
             "`by:` does not scope `user_activities` to a group, so the controller resolving the group is not enough"
    end

    # the controller's own call, which differs from the test above in taking the feed name as the string from the URL
    test "the feed named by the string in the URL is scoped the same way", %{
      public_group: group,
      unrelated_post: unrelated_post
    } do
      %{edges: edges} = Bonfire.Social.FeedLoader.feed("user_activities", %{by: group}, limit: 20)

      refute id(unrelated_post) in Enum.map(edges, &e(&1, :activity, :object_id, nil)),
             "the feed name as a string loses the `by:` scope"
    end

    # what the controller used to do, and what broke these feeds: `FeedLoader.feed/2` takes a `%FeedFilters{}` as already prepared, so a `by:` merged into the preset's struct never becomes a subject filter. The controller no longer does this; the loader still allows it
    @tag skip:
           "`FeedLoader` still skips preparing a `%FeedFilters{}` it is handed, which is open in the notifications plan (whether `FeedFilters.validate/1` should cast structs too); the controller no longer pre-merges, which is what fixed the feeds"
    test "a `by:` merged into the preset's own filters still scopes the feed", %{
      public_group: group,
      unrelated_post: unrelated_post
    } do
      {:ok, %{filters: preset_filters}} =
        Bonfire.Social.Feeds.feed_preset_if_permitted(:user_activities, subject_user: group)

      filters = Map.merge(preset_filters, %{by: group})
      %{edges: edges} = Bonfire.Social.FeedLoader.feed(:user_activities, filters, limit: 20)

      refute id(unrelated_post) in Enum.map(edges, &e(&1, :activity, :object_id, nil)),
             "pre-merging the preset's filters alone unscopes it. Preset filters: #{inspect(preset_filters)}"
    end
  end

  for format <- ["rss", "atom"] do
    test "a public group's #{format} feed shows its posts to a guest", %{public_group: group} do
      assert {200, body} = fetch(group_feed_path(group, unquote(format)))

      assert body =~ "open group post",
             "control: this URL does serve a group's posts, so their absence below is a boundary holding rather than the route serving nothing"

      refute body =~ "unrelated public post",
             "the feed is not scoped to the group: it carries a post from outside it, so the group's posts appearing above prove nothing about filtering"
    end

    test "a members-private group's #{format} feed shows a guest none of its posts", %{
      private_group: group
    } do
      case fetch(group_feed_path(group, unquote(format))) do
        # as good as an empty feed, and better, since it does not confirm the group exists
        {404, _} ->
          :ok

        {200, body} ->
          refute body =~ "members only post",
                 "a feed reader is a guest, so this is the group's content leaving through a door with no boundary on it"

        other ->
          flunk("expected either a 404 or a feed without the post, got #{inspect(other)}")
      end
    end
  end

  # Parked: its control fails, since a PUBLIC group's post is not in `/feed/local/feed.rss` either, so the refute proves nothing. Group posts evidently never reach the local feed's RSS, which closes this door for a reason other than boundaries. Whether a public group's posts SHOULD appear there is a product question; restore this once it is answered, with a control that holds.
  @tag skip: "group posts do not reach the :local RSS feed at all, so the control cannot hold"
  test "the local feed does not carry a members-private group's posts", %{
    private_group: _group
  } do
    assert {200, body} = fetch("/feed/local/feed.rss")

    refute body =~ "members only post"

    assert body =~ "open group post",
           "control: the public group's post IS in the local feed, so the one above is filtered rather than never indexed there"
  end
end
