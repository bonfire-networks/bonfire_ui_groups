defmodule Bonfire.UI.Groups.GroupDiscoveryPreviewTest do
  use Bonfire.UI.Groups.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  alias Bonfire.Classify.Simulate

  test "discovery keeps joining policy while full visibility details remain on the group page",
       context do
    owner = fake_user!(fake_account!())
    group = create_group(owner, "Preview readers", "on_request")
    card = "#group-preview-#{id(group)}"

    conn(user: context.me, account: context.account)
    |> visit("/groups")
    |> assert_has("#{card} [data-role=group-card-membership-policy]", text: "On request")
    |> click_link("#group-preview-link-#{id(group)}", "Preview readers")
    |> assert_has("[data-role=group-hero-visibility]", text: "Discoverable group preview")
    |> assert_has("[data-role=group-hero-membership]", text: "On request")
    |> assert_has("[data-role=group-access-details-content]",
      text: "Access to discussions depends on membership"
    )
  end

  setup do
    Process.put([:bonfire, :feed_live_update_many_preload_mode], :inline)
    Process.put(:federating, false)

    account = fake_account!()
    me = fake_user!(account)

    %{account: account, me: me}
  end

  test "discovery cards show topics and membership without conversation previews or actions", %{
    account: account,
    me: me
  } do
    group = create_group(me, "Accessible systems guild", "local:members")
    Simulate.fake_category!(me, group, %{name: "Accessibility", type: :topic})
    Simulate.fake_post_in_group!(me, group, "<p>What belongs in a shared design token?</p>")
    card = "#group-preview-#{id(group)}"

    conn(user: me, account: account)
    |> visit("/groups")
    |> assert_has("[data-two-columns]")
    |> refute_has("#widgets-drawer")
    |> assert_has("#group-discovery-hero", text: "Find your community")
    |> assert_has("#{card} [data-role=group-card-cover]")
    |> assert_has(card, text: "Accessible systems guild")
    |> assert_has(card, text: "Accessibility")
    |> assert_has(card, text: "1 member")
    |> assert_has("#group-membership-#{id(group)}", text: "Joined")
    |> refute_has("#{card} button")
    |> refute_has(card, text: "What belongs in a shared design token?")
    |> refute_has(card, text: "Recent conversation")
    |> refute_has(card, text: "No topics yet")
    |> refute_has(card, text: "This group has not added a description yet.")
    |> click_link("#group-preview-link-#{id(group)}", "Accessible systems guild")
    |> assert_path("/group/#{group.character.username}")
  end

  test "search includes topics, excludes conversation text, and clearing restores groups", %{
    account: account,
    me: me
  } do
    open_group = create_group(me, "Open makers", "local:members")
    request_group = create_group(me, "Reviewed readers", "on_request")
    Simulate.fake_category!(me, open_group, %{name: "Unusual typography", type: :topic})
    Simulate.fake_post_in_group!(me, open_group, "<p>Choosing accessible typefaces</p>")
    open_card = "#group-preview-#{id(open_group)}"
    request_card = "#group-preview-#{id(request_group)}"

    conn(user: me, account: account)
    |> visit("/groups")
    |> fill_in("Search groups", with: "Unusual typography")
    |> assert_has(open_card)
    |> refute_has(request_card)
    |> fill_in("Search groups", with: "")
    |> assert_has(open_card)
    |> assert_has(request_card)
    |> fill_in("Search groups", with: "accessible typefaces")
    |> assert_has("#group-discovery-empty")
    |> refute_has(open_card)
    |> refute_has(request_card)
    |> fill_in("Search groups", with: "   ")
    |> assert_has(open_card)
    |> assert_has(request_card)
    |> choose("By request")
    |> assert_has(request_card)
    |> refute_has(open_card)
    |> fill_in("Search groups", with: "no matching phrase")
    |> assert_has("#group-discovery-empty")
    |> fill_in("Search groups", with: "")
    |> assert_has(request_card)
    |> refute_has(open_card)
    |> choose("Any joining policy")
    |> assert_has(open_card)
    |> assert_has(request_card)
  end

  test "joined groups use the same cards with real topics and membership data", %{
    account: account,
    me: me
  } do
    group = create_group(me, "Joined makers", "local:members")
    Simulate.fake_category!(me, group, %{name: "Craft", type: :topic})
    card = "#group-joined-grid #group-preview-#{id(group)}"

    conn(user: me, account: account)
    |> visit("/groups?tab=joined")
    |> refute_has("#group-discovery-hero")
    |> assert_has(card, text: "Joined makers")
    |> assert_has(card, text: "Craft")
    |> assert_has(card, text: "1 member")
    |> assert_has("#{card} [data-role=group-card-cover]")
    |> assert_has("#{card} #group-membership-#{id(group)}", text: "Joined")
    |> refute_has("#{card} button")
    |> click_link("#group-preview-link-#{id(group)}", "Joined makers")
    |> assert_path("/group/#{group.character.username}")
  end

  test "Joined includes membership without following and excludes following without membership",
       context do
    owner = fake_user!(fake_account!())
    member_group = create_group(owner, "Membership only", "local:members")
    followed_group = create_group(owner, "Following only", "local:members")
    {:ok, _} = Bonfire.Classify.Categories.join_group(context.me, member_group)
    {:ok, _} = Bonfire.Social.Graph.Follows.follow(context.me, followed_group)

    assert Bonfire.Classify.Categories.member?(context.me, member_group)
    refute Bonfire.Social.Graph.Follows.following?(context.me, member_group)
    refute Bonfire.Classify.Categories.member?(context.me, followed_group)

    conn(user: context.me, account: context.account)
    |> visit("/groups?tab=joined")
    |> assert_has("#group-membership-#{id(member_group)}", text: "Joined")
    |> refute_has("#group-preview-#{id(followed_group)}")
  end

  test "loading more joined groups adds cards with their membership data", %{
    account: account,
    me: me
  } do
    oldest = create_group(me, "Earlier joined group", "local:members")
    create_group(me, "Middle joined group", "local:members")
    latest = create_group(me, "Latest joined group", "local:members")
    Bonfire.Social.Graph.Follows.unfollow(me, oldest)
    Bonfire.Social.Graph.Follows.unfollow(me, latest)
    refute Bonfire.Social.Graph.Follows.following?(me, oldest)
    refute Bonfire.Social.Graph.Follows.following?(me, latest)
    owner = fake_user!(fake_account!())
    followed_only = create_group(owner, "Newer followed-only group", "local:members")
    {:ok, _} = Bonfire.Social.Graph.Follows.follow(me, followed_only)

    conn(user: me, account: account)
    |> visit("/groups?tab=joined")
    |> assert_has("#group-joined-grid article", count: 2)
    |> refute_has("#group-preview-#{id(followed_only)}")
    |> click_button("#load_more_joined", "Load more")
    |> assert_has("#group-joined-grid article", count: 3)
    |> assert_has("#group-membership-#{id(oldest)}", text: "Joined")
    |> assert_has("#group-preview-#{id(oldest)}", text: "1 member")
    |> refute_has("#group-joined-grid article button")
  end

  test "empty policy results explain the filter and can be cleared", %{account: account, me: me} do
    group = create_group(me, "Open garden", "local:members")

    conn(user: me, account: account)
    |> visit("/groups")
    |> choose("By request")
    |> assert_has("#group-discovery-empty", text: "No groups match this joining policy")
    |> refute_has("#group-discovery-empty", text: "No groups here yet")
    |> click_link("Clear filters")
    |> assert_has("#group-preview-#{id(group)}")
  end

  test "nonmember cards omit redundant status and keep the joining policy", %{
    account: account,
    me: me
  } do
    owner = fake_user!(fake_account!())
    group = create_group(owner, "Reading circle", "local:members")
    card = "#group-preview-#{id(group)}"

    conn(user: me, account: account)
    |> visit("/groups")
    |> refute_has("#group-membership-#{id(group)}")
    |> assert_has("#{card} [data-role=group-card-membership-policy]")
    |> refute_has("#{card} button")
  end

  test "search can be submitted through URL parameters", %{account: account, me: me} do
    group = create_group(me, "Needle group", "local:members")
    other = create_group(me, "Another group", "local:members")

    params =
      URI.encode_query(%{
        "group_filters[search_term]" => "Needle",
        "group_filters[join_filter]" => "open"
      })

    conn(user: me, account: account)
    |> visit("/groups?#{params}")
    |> assert_has("#group-preview-#{id(group)}")
    |> refute_has("#group-preview-#{id(other)}")
    |> fill_in("Search groups", with: "")
    |> assert_has("#group-preview-#{id(other)}")
  end

  test "filters keep pagination available and clearing restores loaded pages", %{
    account: account,
    me: me
  } do
    group = create_group(me, "Older needle group", "local:members")
    create_group(me, "Newer garden", "local:members")
    create_group(me, "Newest workshop", "local:members")

    conn(user: me, account: account)
    |> visit("/groups")
    |> fill_in("Search groups", with: "Older needle")
    |> choose("Open to join")
    |> assert_has("#group-discovery-empty", text: "No matching groups loaded yet")
    |> click_button("[data-id=load_more]", "Load more")
    |> assert_has("#group-preview-#{id(group)}")
    |> refute_has("#group-discovery-grid", text: "Newer garden")
    |> fill_in("Search groups", with: "")
    |> assert_has("#group-discovery-grid", text: "Older needle group")
    |> assert_has("#group-discovery-grid", text: "Newer garden")
    |> assert_has("#group-discovery-grid", text: "Newest workshop")
  end

  test "search and clear stay within the selected group view", %{account: account, me: me} do
    joined = create_group(me, "Shared garden", "local:members")
    archived = create_group(me, "Archived garden", "local:members")
    {:ok, _} = Bonfire.Classify.Categories.soft_delete(archived, me)

    conn(user: me, account: account)
    |> visit("/groups")
    |> refute_has("#group-preview-#{id(archived)}")
    |> fill_in("Search groups", with: "garden")
    |> PhoenixTest.select("Group view", option: "Joined")
    |> assert_has("#group-joined-grid #group-preview-#{id(joined)}")
    |> fill_in("Search groups", with: "missing")
    |> fill_in("Search groups", with: "")
    |> assert_has("#group-view-filter option[selected]", text: "Joined")
    |> assert_has("#group-preview-#{id(joined)}")
    |> PhoenixTest.select("Group view", option: "Archived")
    |> assert_has("a", text: "Archived garden")
    |> refute_has("#group-preview-#{id(joined)}")
    |> fill_in("Search groups", with: "missing")
    |> refute_has("a", text: "Archived garden")
    |> fill_in("Search groups", with: "")
    |> assert_has("a", text: "Archived garden")
    |> assert_has("#group-view-filter option[selected]", text: "Archived")
    |> PhoenixTest.select("Group view", option: "All groups")
    |> assert_has("#group-preview-#{id(joined)}")
    |> refute_has("#group-preview-#{id(archived)}")
  end

  test "clear filters resets the search without leaving Joined", %{account: account, me: me} do
    group = create_group(me, "Joined garden", "local:members")

    conn(user: me, account: account)
    |> visit("/groups?tab=joined")
    |> fill_in("Search groups", with: "missing")
    |> click_link("Clear filters")
    |> assert_has("#group-view-filter option[selected]", text: "Joined")
    |> assert_has("#group-discovery-search:not([value]), #group-discovery-search[value='']")
    |> assert_has("#group-preview-#{id(group)}")
  end

  defp create_group(user, name, membership) do
    Simulate.fake_group!(user, %{
      name: name,
      membership: membership,
      visibility: "nonfederated:preview",
      participation: "local:contributors",
      default_content_visibility: "nonfederated"
    })
  end
end
