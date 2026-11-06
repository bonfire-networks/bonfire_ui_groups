defmodule Bonfire.UI.Groups.DashboardMyGroupsFeedTest do
  @moduledoc """
  My groups in the dashboard's "Latest activity" feed: a member who chooses it as their default feed sees their groups' posts at the end of the dashboard, and its tab stays while another tab is open.

  The feed's query is covered in `Bonfire.Classify.GroupFeedPresetsTest`; the default feed's tab and the dropdown in `Bonfire.UI.Me.DashboardSettingsTest`.
  """
  use Bonfire.UI.Groups.ConnCase, async: false
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

    group_a = Simulate.fake_group!(owner, Map.put(@open_group, :name, "Dashboard Joined Group"))
    group_b = Simulate.fake_group!(owner, Map.put(@open_group, :name, "Dashboard Other Group"))

    {:ok, _} = Categories.join_group(me, group_a)
    assert Categories.member?(me, group_a)

    Simulate.fake_post_in_group!(owner, group_a, "<p>A post in my dashboard group</p>")
    Simulate.fake_post_in_group!(owner, group_b, "<p>A post in the other dashboard group</p>")

    # keep the user each put returns, as settings are preloaded on it
    {:ok, %{__context__: %{current_user: me}}} =
      Bonfire.Common.Settings.put([Bonfire.Web.Views.DashboardLive, :include, :feed], true,
        current_user: me
      )

    %{account: account, me: me}
  end

  defp default_my_groups(me) do
    {:ok, %{__context__: %{current_user: me}}} =
      Bonfire.Common.Settings.put([Bonfire.UI.Social.FeedLive, :default_feed], :my_groups,
        current_user: me
      )

    me
  end

  test "a member whose default feed is My groups sees their groups' posts on the dashboard", %{
    account: account,
    me: me
  } do
    me = default_my_groups(me)

    conn(user: me, account: account)
    |> visit("/dashboard")
    |> wait_async()
    |> assert_has("[data-id=dashboard_feed] article", text: "A post in my dashboard group")
    |> assert_has("[data-id=dashboard_feed] [data-role=published_in]",
      text: "Dashboard Joined Group"
    )
    |> refute_has("[data-id=dashboard_feed] article", text: "A post in the other dashboard group")
    |> assert_has("[data-id=dashboard_feed] #feed-tab-my_groups[aria-current=page]")
  end

  test "the My groups tab stays when another tab is open", %{account: account, me: me} do
    me = default_my_groups(me)

    conn(user: me, account: account)
    |> visit("/dashboard?feed=local")
    |> wait_async()
    |> assert_has("[data-id=dashboard_feed] #feed-tab-local[aria-current=page]")
    |> assert_has(
      "[data-id=dashboard_feed] a#feed-tab-my_groups[href='/dashboard?feed=my_groups']"
    )
  end

  test "choosing My groups in the dashboard settings puts it on the dashboard", %{
    account: account,
    me: me
  } do
    conn(user: me, account: account)
    |> visit("/dashboard")
    |> wait_async()
    |> refute_has("[data-id=dashboard_feed] #feed-tab-my_groups")
    |> visit("/settings/user/dashboard")
    # by its selector, not within the block: `within` hides the form the select belongs to
    |> PhoenixTest.select(
      "[data-role=dashboard_feed_setting] #dashboard-default-feed-select",
      "Default feed",
      option: "My groups"
    )
    |> visit("/dashboard")
    |> wait_async()
    |> assert_has("[data-id=dashboard_feed] #feed-tab-my_groups[aria-current=page]")
    |> assert_has("[data-id=dashboard_feed] article", text: "A post in my dashboard group")
  end

  test "a member of no group with My groups as default sees the generic empty feed" do
    account = fake_account!()
    loner = fake_user!(account)

    {:ok, %{__context__: %{current_user: loner}}} =
      Bonfire.Common.Settings.put([Bonfire.Web.Views.DashboardLive, :include, :feed], true,
        current_user: loner
      )

    loner = default_my_groups(loner)

    # the setup's posts are public: only membership keeps them out
    conn(user: loner, account: account)
    |> visit("/dashboard")
    |> wait_async()
    |> assert_has("[data-id=dashboard_feed] #feed-tab-my_groups[aria-current=page]")
    |> assert_has("[data-id=dashboard_feed] [data-id=feed]")
    # no custom empty state: the feed ends as any empty feed does (with a time limit, its "Last N days" line rather than `EmptyFeed`)
    |> refute_has("[data-id=dashboard_feed] article")
  end
end
