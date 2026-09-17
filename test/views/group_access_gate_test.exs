defmodule Bonfire.UI.Groups.GroupAccessGateTest do
  use Bonfire.UI.Groups.ConnCase, async: false
  @moduletag :ui

  doctest Bonfire.UI.Groups.AccessGateLive, import: true

  setup do
    Process.put([:bonfire, :feed_live_update_many_preload_mode], :inline)
    account = fake_account!()
    owner = fake_user!(account)

    group =
      Bonfire.Classify.Simulate.fake_group!(owner, %{
        name: "Preview club",
        membership: "on_request",
        visibility: "nonfederated:preview",
        participation: "group_members"
      })

    Bonfire.Classify.Simulate.fake_post_in_group!(owner, group, "<p>Restricted discussion</p>")
    %{account: account, owner: owner, group: group}
  end

  test "guests see the hero and sign-in overlay without a feed", %{group: group} do
    conn()
    |> visit("/&#{group.character.username}")
    |> wait_async()
    |> assert_has("h1", text: "Preview club")
    |> assert_has("#group_access_gate a[href^='/login?go=']", text: "Sign in")
    |> refute_has("[data-id=feed]")
    |> refute_has("[data-id=group]", text: "Restricted discussion")
    |> refute_has("#inline_composer_placeholder")
  end

  test "signed-in nonmembers still see the gate without a sign-in action", context do
    visitor = fake_user!(context.account)

    conn(user: visitor, account: context.account)
    |> visit("/&#{context.group.character.username}")
    |> wait_async()
    |> assert_has("#group_access_gate")
    |> refute_has("#group_access_gate a")
    |> refute_has("[data-id=feed]")
    |> refute_has("#inline_composer_placeholder")
  end

  test "members see their feed instead of the gate", context do
    conn(user: context.owner, account: context.account)
    |> visit("/&#{context.group.character.username}")
    |> wait_async()
    |> refute_has("#group_access_gate")
    |> assert_has("[data-id=feed]", text: "Restricted discussion")
  end

  test "a restricted post default does not gate a readable group", context do
    group =
      Bonfire.Classify.Simulate.fake_group!(context.owner, %{
        name: "Readable group",
        visibility: "nonfederated",
        default_content_visibility: "local"
      })

    conn()
    |> visit("/&#{group.character.username}")
    |> wait_async()
    |> refute_has("#group_access_gate")
    |> refute_has("[data-role=category_preview]")
  end
end
