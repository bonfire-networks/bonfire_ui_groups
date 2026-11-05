defmodule Bonfire.UI.Groups.GroupFeedPresetsUITest do
  @moduledoc """
  The "My groups" and "All known groups" feeds as pages: `/feed/my_groups` and `/feed/known_groups` show what is published in groups, with the group each post is in, and the feeds menu links to both.

  Their queries are covered in `Bonfire.Classify.GroupFeedPresetsTest`; this is what a reader sees.
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
    account = fake_account!()
    me = fake_user!(account)
    creator = fake_user!()

    group_a = Simulate.fake_group!(creator, Map.put(@open_group, :name, "Joined Feed Group"))
    group_b = Simulate.fake_group!(creator, Map.put(@open_group, :name, "Other Feed Group"))

    {:ok, _} = Categories.join_group(me, group_a)

    Simulate.fake_post_in_group!(creator, group_a, "<p>A post in the joined group</p>")
    Simulate.fake_post_in_group!(creator, group_b, "<p>A post in the other group</p>")

    %{account: account, me: me}
  end

  test "My groups shows the posts in my groups, with the group they are in", %{
    account: account,
    me: me
  } do
    conn(user: me, account: account)
    |> visit("/feed/my_groups")
    |> wait_async()
    |> assert_has("[data-id=feed] article", text: "A post in the joined group")
    |> assert_has("[data-id=feed] [data-role=published_in]", text: "Joined Feed Group")
    |> refute_has("[data-id=feed] article", text: "A post in the other group")
  end

  # Disabled: guests reach All known groups through the Activity view of /groups, not here. `/feed/:tab` stays for signed-in users only (`:user_required` in `Bonfire.UI.Social.Routes`), so a guest visiting it is sent to log in. The guest case belongs with the /groups Activity view tests
  # test "All known groups shows a public group's posts to a guest" do
  #   conn()
  #   |> visit("/feed/known_groups")
  #   |> wait_async()
  #   |> assert_has("[data-id=feed] article", text: "A post in the other group")
  #   |> assert_has("[data-id=feed] [data-role=published_in]", text: "Other Feed Group")
  # end

  # was "the feeds menu lists My groups and All known groups": /groups now has both feeds (`/groups/feed` and `/groups/feed/all`), so the feeds menu no longer lists them by default, while their pages keep working (the test above)
  test "the feeds menu doesn't list My groups and All known groups", %{account: account, me: me} do
    conn(user: me, account: account)
    |> visit("/feed/local")
    |> wait_async()
    |> assert_has("[id^=feed-tab-]")
    |> refute_has("#feed-tab-my_groups")
    |> refute_has("#feed-tab-known_groups")
  end

  # a group's posts reach its outbox as the group's boosts, so hiding boosts is an activity type that visibly narrows this feed
  test "the feed's own controls narrow My groups", %{account: account, me: me} do
    conn(user: me, account: account)
    |> visit("/feed/my_groups")
    |> wait_async()
    |> assert_has("[data-id=feed] article", text: "A post in the joined group")
    |> click_button("[data-role=open_modal]", "More filters")
    |> click_button("[data-toggle='boost'] button", "Hide")
    |> click_button("Apply filters")
    |> wait_async()
    |> refute_has("[data-id=feed] article", text: "A post in the joined group")
  end
end
