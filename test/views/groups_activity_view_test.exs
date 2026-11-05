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
    |> click_link("#group-mode-switch a", "Groups")
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
end
