defmodule Bonfire.UI.Groups.GroupsActivityViewTest do
  @moduledoc """
  Each /groups route renders its view: the directory views (`/groups/discover`, `/groups/joined`, `/groups/archived`) list groups, and the feed views (`/groups/feed`, `/groups/feed/all`) show what is published in them. A two-link switch, "Groups" and "Latest updates", moves between a directory view and its feed.

  The feeds' queries are covered in `Bonfire.Classify.GroupFeedPresetsTest`, and `/feed/my_groups` in `Bonfire.UI.Groups.GroupFeedPresetsUITest`; this is what a reader of /groups sees.
  """
  use Bonfire.UI.Groups.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  alias Bonfire.Classify.Categories
  alias Bonfire.Classify.Simulate

  # open and public, since a group made with no dimensions reviews joins and would leave the join a request
  @open_group %{
    membership: "open",
    visibility: "global",
    participation: "anyone",
    default_content_visibility: "public"
  }

  setup do
    Process.put([:bonfire, :feed_live_update_many_preload_mode], :inline)
    Process.put(:federating, false)
    # the origin and sort tests put three or more group posts on one page
    Process.put([:bonfire, :default_pagination_limit], 10)

    account = fake_account!()
    me = fake_user!(account)
    owner = fake_user!()

    group_a = Simulate.fake_group!(owner, Map.put(@open_group, :name, "Joined Activity Group"))
    group_b = Simulate.fake_group!(owner, Map.put(@open_group, :name, "Other Activity Group"))

    {:ok, _} = Categories.join_group(me, group_a)

    Simulate.fake_post_in_group!(owner, group_a, "<p>A post in the joined group</p>")
    Simulate.fake_post_in_group!(owner, group_b, "<p>A post in the other group</p>")

    group_d = Simulate.fake_group!(me, Map.put(@open_group, :name, "Archived Activity Group"))
    {:ok, _} = Categories.soft_delete(group_d, me)

    %{account: account, me: me, group_a: group_a, group_b: group_b}
  end

  test "/groups/discover shows every group's card, and Latest updates goes to its feed", %{
    account: account,
    me: me,
    group_a: group_a,
    group_b: group_b
  } do
    conn(user: me, account: account)
    |> visit("/groups/discover")
    |> assert_has("#group-preview-#{id(group_a)}")
    |> assert_has("#group-preview-#{id(group_b)}")
    |> refute_has("[data-role=published_in]")
    |> click_link("#group-mode-switch a", "Latest updates")
    |> assert_path("/groups/feed/all")
  end

  test "/groups/feed/all shows posts from every group, with the group they are in", %{
    account: account,
    me: me
  } do
    conn(user: me, account: account)
    |> visit("/groups/feed/all")
    |> wait_async()
    |> assert_has("[data-id=feed] article", text: "A post in the joined group")
    |> assert_has("[data-id=feed] article", text: "A post in the other group")
    |> assert_has("[data-id=feed] [data-role=published_in]", text: "Joined Activity Group")
    |> assert_has("[data-id=feed] [data-role=published_in]", text: "Other Activity Group")
    |> refute_has("#group-discovery-grid")
  end

  test "/groups/feed shows posts from my groups only", %{account: account, me: me} do
    conn(user: me, account: account)
    |> visit("/groups/feed")
    |> wait_async()
    |> assert_has("[data-id=feed] article", text: "A post in the joined group")
    |> refute_has("[data-id=feed] article", text: "A post in the other group")
  end

  test "/groups/joined shows my groups' cards and pairs with /groups/feed", %{
    account: account,
    me: me,
    group_a: group_a,
    group_b: group_b
  } do
    conn(user: me, account: account)
    |> visit("/groups/joined")
    |> assert_has("#group-preview-#{id(group_a)}")
    |> refute_has("#group-preview-#{id(group_b)}")
    |> click_link("#group-mode-switch a", "Latest updates")
    |> assert_path("/groups/feed")
    |> refute_has("#group-mode-switch a", text: "Groups")
    |> click_link("#group-mode-switch a", "Directory")
    |> assert_path("/groups/joined")
  end

  test "a view keeps the mode", %{account: account, me: me} do
    conn(user: me, account: account)
    |> visit("/groups/feed/all")
    |> choose("Joined")
    |> assert_path("/groups/feed")

    conn(user: me, account: account)
    |> visit("/groups/discover")
    |> choose("Joined")
    |> assert_path("/groups/joined")
    |> assert_has("#group-view-joined[checked]")
  end

  test "/groups/archived lists archived groups, with no Latest updates link", %{
    account: account,
    me: me
  } do
    conn(user: me, account: account)
    |> visit("/groups/archived")
    |> assert_has("a", text: "Archived Activity Group")
    |> refute_has("#group-mode-switch")
  end

  # a group's posts reach its outbox as the group's boosts, so hiding boosts is an activity type that visibly narrows this feed (the media filters are WIP)
  test "the feed's own controls narrow the chosen groups", %{account: account, me: me} do
    conn(user: me, account: account)
    |> visit("/groups/feed")
    |> wait_async()
    |> assert_has("[data-id=feed] article", text: "A post in the joined group")
    |> click_button("[data-role=open_modal]", "More filters")
    |> click_button("[data-toggle='boost'] button", "Hide")
    |> click_button("Apply filters")
    |> wait_async()
    |> refute_has("[data-id=feed] article", text: "A post in the joined group")
  end

  # how guests reach All known groups, as `/feed/known_groups` is for signed-in users only
  test "a guest reads every visible group's feed at /groups/feed/all" do
    conn()
    |> visit("/groups/feed/all")
    |> wait_async()
    |> assert_has("[data-id=feed] article", text: "A post in the other group")
  end

  # by where each group is hosted, as in the directory; these groups are all local
  test "the origin menu narrows the feed and stays in the URL", %{account: account, me: me} do
    conn(user: me, account: account)
    |> visit("/groups/feed/all")
    |> choose("This instance")
    |> wait_async()
    |> assert_has("[data-id=feed] article", text: "A post in the joined group")
    |> choose("Other instances")
    |> wait_async()
    |> assert_path("/groups/feed/all", query_params: %{"origin" => "remote"})
    |> refute_has("[data-id=feed] article", text: "A post in the joined group")
  end

  test "the switch keeps the origin", %{account: account, me: me} do
    conn(user: me, account: account)
    |> visit("/groups/discover?origin=local")
    |> click_link("#group-mode-switch a", "Latest updates")
    |> assert_path("/groups/feed/all", query_params: %{"origin" => "local"})
  end

  # the search box and the joining policy choose groups, not posts, so they belong to the directory
  test "the feed views show the origin menu, with no search box and no joining-policy menu", %{
    account: account,
    me: me
  } do
    for path <- ["/groups/feed/all", "/groups/feed"] do
      conn(user: me, account: account)
      |> visit(path)
      |> assert_has("#group-origin-filters")
      |> refute_has("#group-discovery-search")
      |> refute_has("#group-policy-filters")
      |> refute_has("#group-index-filters")
    end
  end

  test "Archived search filters the archived groups", %{account: account, me: me} do
    group_e = Simulate.fake_group!(me, Map.put(@open_group, :name, "Shelved Second Group"))
    {:ok, _} = Categories.soft_delete(group_e, me)

    conn(user: me, account: account)
    |> visit("/groups/archived")
    |> assert_has("a", text: "Archived Activity Group")
    |> assert_has("a", text: "Shelved Second Group")
    |> fill_in("Search groups", with: "Archived Activity")
    |> assert_has("a", text: "Archived Activity Group")
    |> refute_has("a", text: "Shelved Second Group")
  end

  # a feed of group activities only, so switching them off would empty it
  test "the feed views hide the Group activities control, which a normal feed keeps", %{
    account: account,
    me: me
  } do
    conn(user: me, account: account)
    |> visit("/feed/local")
    |> wait_async()
    |> assert_has("input[name='scope[group_activity]']")

    conn(user: me, account: account)
    |> visit("/groups/feed/all")
    |> wait_async()
    |> assert_has("input[name='scope[boosts]']")
    |> refute_has("input[name='scope[group_activity]']")
  end

  # the /groups origin menu chooses the groups by where they are hosted, so "More filters" leaves its own Origin out there, which a normal feed keeps
  test "the feed views have no Origin in More filters, and keep the origin menu", %{
    account: account,
    me: me
  } do
    conn(user: me, account: account)
    |> visit("/feed/local")
    |> wait_async()
    |> click_button("[data-role=open_modal]", "More filters")
    |> assert_has("[data-row=origin]")

    for path <- ["/groups/feed", "/groups/feed/all"] do
      conn(user: me, account: account)
      |> visit(path)
      |> wait_async()
      |> assert_has("#group-origin-filters")
      |> click_button("[data-role=open_modal]", "More filters")
      |> assert_has("[data-row=hashtags]")
      |> refute_has("[data-row=origin]")
    end
  end

  # archived groups have no feed, and the origin menu joins the view tabs' row
  test "the feed views have no Archived tab, and the origin menu sits in the tabs row", %{
    account: account,
    me: me
  } do
    conn(user: me, account: account)
    |> visit("/groups/feed/all")
    |> assert_has("#group-view-joined")
    |> refute_has("#group-view-archived")
    |> assert_has("#group-view-filter #group-origin-filters")

    conn(user: me, account: account)
    |> visit("/groups/discover")
    |> assert_has("#group-view-archived")
  end

  test "the first tab reads All known groups, in the directory and the feed", %{
    account: account,
    me: me
  } do
    for path <- ["/groups/discover", "/groups/feed/all"] do
      conn(user: me, account: account)
      |> visit(path)
      |> assert_has("label[for=group-view-discover]", text: "All known groups")
    end
  end

  test "the tab query param no longer picks a view", %{group_b: group_b} do
    account = fake_account!()
    loner = fake_user!(account)

    conn(user: loner, account: account)
    |> visit("/groups?tab=joined")
    |> assert_has("#group-preview-#{id(group_b)}")
  end

  # `me` is a member of a group on this instance and of one mirrored from elsewhere, each with a post, so each origin has something to show and something to hide
  describe "origin on the feed views" do
    # the label id is prefixed with the component id (the editor can mount twice on a page)
    @origin_scope "[role=radiogroup][aria-labelledby$='_origin_label']"
    @local_post "A post in the joined group"
    @remote_post "A post in the mirrored group"

    setup %{me: me} do
      owner = fake_user!()

      mirrored =
        Simulate.fake_group!(owner, Map.put(@open_group, :name, "Mirrored Activity Group"))

      {:ok, _} = Categories.join_group(me, mirrored)
      Simulate.fake_post_in_group!(owner, mirrored, "<p>#{@remote_post}</p>")

      # a `Peered` row is what makes a group a mirror of one hosted elsewhere
      assert {:ok, _} =
               Bonfire.Federate.ActivityPub.Peered.save_canonical_uri(
                 mirrored,
                 "https://elsewhere.local/c/mirrored_activity"
               )

      :ok
    end

    for path <- ["/groups/feed", "/groups/feed/all"] do
      test "#{path} shows both groups' posts with no origin chosen", %{
        account: account,
        me: me
      } do
        conn(user: me, account: account)
        |> visit(unquote(path))
        |> wait_async()
        |> assert_has("[data-id=feed] article", text: @local_post)
        |> assert_has("[data-id=feed] article", text: @remote_post)
      end

      for {label, origin, shown, hidden} <- [
            {"This instance", "local", @local_post, @remote_post},
            {"Other instances", "remote", @remote_post, @local_post}
          ] do
        test "#{path}: the origin menu's #{label} shows only its group's post, and stays in the URL",
             %{account: account, me: me} do
          conn(user: me, account: account)
          |> visit(unquote(path))
          |> wait_async()
          |> assert_has("[data-id=feed] article", text: @local_post)
          |> assert_has("[data-id=feed] article", text: @remote_post)
          |> choose(unquote(label))
          |> wait_async()
          |> assert_has("[data-id=feed] article", text: unquote(shown))
          |> refute_has("[data-id=feed] article", text: unquote(hidden))
          |> assert_path(unquote(path), query_params: %{"origin" => unquote(origin)})
        end

        # Under the `:addressed` strategy, Origin becomes a locality-bucket check that no group-outbox row matches, so it empties outbox-limited feeds; it passes under `or_filter`
        @tag :todo
        test "#{path}: More filters' origin #{label} shows only its group's post", %{
          account: account,
          me: me
        } do
          conn(user: me, account: account)
          |> visit(unquote(path))
          |> wait_async()
          |> assert_has("[data-id=feed] article", text: @local_post)
          |> assert_has("[data-id=feed] article", text: @remote_post)
          |> click_button("[data-role=open_modal]", "More filters")
          |> click_button("#{@origin_scope} [role=radio]", unquote(label))
          |> click_button("Apply filters")
          |> wait_async()
          |> assert_has("[data-id=feed] article", text: unquote(shown))
          |> refute_has("[data-id=feed] article", text: unquote(hidden))
        end
      end
    end
  end

  # two posts in the joined group: the older one has replies, the newer one has none, so newest first and most replied put them in opposite orders
  describe "Most replied on the feed views" do
    @replied_post "An older post with replies"
    @quiet_post "A newer post without replies"

    setup %{group_a: group_a} do
      author = fake_user!()
      replier = fake_user!()

      replied = Simulate.fake_post_in_group!(author, group_a, "<p>#{@replied_post}</p>")

      # replies in the group, as a member replying there makes them, so they are in its outbox and in the post's thread
      {:ok, _} = Categories.join_group(replier, group_a)

      for n <- 1..2 do
        {:ok, _} =
          Bonfire.Posts.publish(
            current_user: replier,
            post_attrs: %{
              post_content: %{html_body: "<p>reply #{n}</p>"},
              reply_to_id: replied.id
            },
            publish_in: group_a.id,
            boundary: Bonfire.Classify.Boundaries.read_default_content_visibility(group_a)
          )
      end

      Simulate.fake_post_in_group!(author, group_a, "<p>#{@quiet_post}</p>")

      :ok
    end

    for path <- ["/groups/feed", "/groups/feed/all"] do
      test "#{path}: Most replied puts the post with more replies first", %{
        account: account,
        me: me
      } do
        conn(user: me, account: account)
        |> visit(unquote(path))
        |> wait_async()
        |> assert_feed_order(@quiet_post, @replied_post)
        |> PhoenixTest.select("Sort", option: "Most replied")
        |> wait_async()
        |> assert_has("select[name=feed_order] option[value=reply_count][selected]")
        |> assert_feed_order(@replied_post, @quiet_post)
      end
    end
  end

  # a guest has no menus to choose with, so /groups shows them only the mode switch
  describe "as a guest" do
    test "a signed-in user has the search box, the filter menus and the feed's customise widget",
         %{account: account, me: me} do
      conn(user: me, account: account)
      |> visit("/groups/discover")
      |> assert_has("#group-discovery-search")
      |> assert_has("#group-origin-filters")
      |> assert_has("#group-policy-filters")

      conn(user: me, account: account)
      |> visit("/groups/feed/all")
      |> wait_async()
      |> assert_has("#group-origin-filters")
      |> assert_has("[data-role=feed_advanced_filters]")
    end

    for path <- ["/groups", "/groups/discover", "/groups/feed/all"] do
      test "#{path} shows a guest no search box and no filter menus, and keeps the mode switch" do
        conn()
        |> visit(unquote(path))
        |> wait_async()
        |> assert_has("#group-mode-switch")
        |> refute_has("#group-discovery-search")
        |> refute_has("#group-origin-filters")
        |> refute_has("#group-policy-filters")
        |> refute_has("#group-index-filters")
      end
    end

    test "/groups/feed/all shows a guest no customise widget" do
      conn()
      |> visit("/groups/feed/all")
      |> wait_async()
      |> assert_has("[data-id=feed] article", text: "A post in the other group")
      |> refute_has("[data-role=feed_advanced_filters]")
      |> refute_has("select[name=feed_order]")
    end

    # with no origin menu to change it, a guest's origin is this instance
    test "a signed-in user sees local and mirrored groups and posts with no origin chosen", %{
      account: account,
      me: me,
      group_b: group_b
    } do
      mirrored = mirrored_group_with_post!()

      conn(user: me, account: account)
      |> visit("/groups/discover")
      |> assert_has("#group-preview-#{id(group_b)}")
      |> assert_has("#group-preview-#{id(mirrored)}")

      conn(user: me, account: account)
      |> visit("/groups/feed/all")
      |> wait_async()
      |> assert_has("[data-id=feed] article", text: "A post in the other group")
      |> assert_has("[data-id=feed] article", text: "A post in the mirrored group")
    end

    for path <- ["/groups", "/groups/discover"] do
      test "#{path} lists only this instance's groups to a guest", %{group_b: group_b} do
        mirrored = mirrored_group_with_post!()

        conn()
        |> visit(unquote(path))
        |> assert_has("#group-preview-#{id(group_b)}")
        |> refute_has("#group-preview-#{id(mirrored)}")
      end
    end

    test "/groups/feed/all shows a guest only posts in this instance's groups" do
      mirrored_group_with_post!()

      conn()
      |> visit("/groups/feed/all")
      |> wait_async()
      |> assert_has("[data-id=feed] article", text: "A post in the other group")
      |> refute_has("[data-id=feed] article", text: "A post in the mirrored group")
    end
  end

  # four public groups on this instance, each page holding two, and four posts in them
  describe "guest pagination" do
    setup %{group_b: group_b} do
      Process.put([:bonfire, :default_pagination_limit], 2)

      owner = fake_user!()

      for n <- 1..2 do
        Simulate.fake_group!(owner, Map.put(@open_group, :name, "Paged Group #{n}"))

        Simulate.fake_post_in_group!(
          owner,
          group_b,
          "<p>Another post #{n} in the other group</p>"
        )
      end

      :ok
    end

    test "Load more shows a guest the directory's next groups" do
      conn()
      |> visit("/groups/discover")
      |> assert_has("article[id^=group-preview-]", count: 2)
      |> click_button("[data-id=load_more]", "Load more")
      |> assert_has("article[id^=group-preview-]", count: 4)
    end

    test "Load more shows a guest the feed's next posts" do
      conn()
      |> visit("/groups/feed/all")
      |> wait_async()
      |> assert_has("[data-id=feed] article", count: 2)
      |> click_button("[data-id=load_more]", "Load more")
      |> wait_async()
      |> assert_has("[data-id=feed] article", count: 4)
    end

    # the link a browser without JavaScript follows
    for {path, selector} <- [
          {"/groups/discover", "article[id^=group-preview-]"},
          {"/groups/feed/all", "[data-id=feed] article"}
        ] do
      test "#{path}: Next page shows a guest the next page, without JavaScript" do
        session =
          conn()
          |> visit(unquote(path))
          |> wait_async()
          |> assert_has(unquote(selector), count: 2)

        first_page = shown_ids(session, unquote(selector))

        session =
          session
          |> click_link("a[data-id=next_page]", "Next page")
          |> wait_async()
          |> assert_has(unquote(selector), count: 2)

        next_page = shown_ids(session, unquote(selector))

        assert MapSet.disjoint?(MapSet.new(first_page), MapSet.new(next_page)),
               "the next page should not repeat the first page's #{inspect(first_page)}, got #{inspect(next_page)}"
      end
    end

    # what a guest's browser gets: the static render only, with no LiveView connected, which PhoenixTest's `visit` always does. `/groups` opens on the directory for a guest, who has joined no groups, unless the instance's "Groups page opens on" names the feed
    for {path, default_view, view, selector} <- [
          {"/groups", nil, :discover, "article[id^=group-preview-]"},
          {"/groups/", nil, :discover, "article[id^=group-preview-]"},
          {"/groups", :feed_all, :feed_all, "[data-id=feed] article"},
          {"/groups/discover", nil, :discover, "article[id^=group-preview-]"},
          {"/groups/feed/all", nil, :feed_all, "[data-id=feed] article"}
        ] do
      test "#{path}#{if default_view, do: " opening on #{default_view}"}: the static render of Next page shows a guest the next page, at the view's own path" do
        if unquote(default_view),
          do:
            Process.put(
              [:bonfire_ui_groups, Bonfire.UI.Groups, :default_view],
              unquote(default_view)
            )

        first_html = conn() |> get(unquote(path)) |> html_response(200)
        first_page = static_ids(first_html, unquote(selector))

        assert length(first_page) == 2,
               "the first page should show 2, got #{inspect(first_page)}"

        assert [href] =
                 first_html
                 |> Floki.parse_document!()
                 |> Floki.find("a[data-id=next_page]")
                 |> Floki.attribute("href")

        %URI{path: next_path, query: next_query} = URI.parse(href)

        next_page =
          conn()
          |> get("#{next_path}?#{next_query}")
          |> html_response(200)
          |> static_ids(unquote(selector))

        assert next_page != [], "the next page (#{href}) should show the next items, got none"

        assert MapSet.disjoint?(MapSet.new(first_page), MapSet.new(next_page)),
               "the next page (#{href}) should not repeat the first page's #{inspect(first_page)}, got #{inspect(next_page)}"

        assert next_path == Bonfire.UI.Groups.ExploreLive.view_path(unquote(view)),
               "Next page should link to the view's own path, got #{href}"
      end
    end
  end

  defp static_ids(html, selector) do
    html
    |> Floki.parse_document!()
    |> Floki.find(selector)
    |> Floki.attribute("id")
  end

  # the ids of the elements `selector` finds on the page; `unwrap` returns the session, so they come back as a message
  defp shown_ids(session, selector) do
    PhoenixTest.unwrap(session, fn view ->
      html = Phoenix.LiveViewTest.render(view)

      ids =
        html
        |> Floki.parse_document!()
        |> Floki.find(selector)
        |> Floki.attribute("id")

      send(self(), {:shown_ids, ids})
      html
    end)

    assert_received {:shown_ids, ids}
    ids
  end

  # a public group with a post, mirrored from another instance through a `Peered` row
  defp mirrored_group_with_post! do
    owner = fake_user!()

    mirrored =
      Simulate.fake_group!(owner, Map.put(@open_group, :name, "Mirrored Public Group"))

    Simulate.fake_post_in_group!(owner, mirrored, "<p>A post in the mirrored group</p>")

    assert {:ok, _} =
             Bonfire.Federate.ActivityPub.Peered.save_canonical_uri(
               mirrored,
               "https://elsewhere.local/c/mirrored_public"
             )

    mirrored
  end

  # both texts are in the feed, `first` in an article above `second`'s
  defp assert_feed_order(session, first, second) do
    PhoenixTest.unwrap(session, fn view ->
      html = Phoenix.LiveViewTest.render(view)

      texts =
        html
        |> Floki.parse_document!()
        |> Floki.find("[data-id=feed] article")
        |> Enum.map(&Floki.text/1)

      first_at = Enum.find_index(texts, &(&1 =~ first))
      second_at = Enum.find_index(texts, &(&1 =~ second))

      assert first_at, "#{inspect(first)} should be in the feed"
      assert second_at, "#{inspect(second)} should be in the feed"

      assert first_at < second_at,
             "#{inspect(first)} (article #{first_at}) should come before #{inspect(second)} (article #{second_at})"

      html
    end)
  end
end
