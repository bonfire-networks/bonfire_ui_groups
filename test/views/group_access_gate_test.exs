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

  # A members-private group denies guests `:see` as well as `:read`, unlike the preview club above, so there is no hero a guest is entitled to. They still arrive here: from a pasted link, a remote profile, and the `/pub/group/<id>` redirect, which lands on the `/group/` path. Whatever the page shows them, it must not be an error.
  for path_fun <- [:friendly, :group_path] do
    test "a guest opening a members-private group (#{path_fun}) gets a not-found page, not a crash",
         context do
      group =
        Bonfire.Classify.Simulate.fake_group!(context.owner, %{
          name: "Members only club",
          membership: "invite_only",
          visibility: "members:private",
          participation: "group_members",
          default_content_visibility: "members:private"
        })

      Bonfire.Classify.Simulate.fake_post_in_group!(
        context.owner,
        group,
        "<p>members only talk</p>"
      )

      path =
        case unquote(path_fun) do
          :friendly -> "/&#{group.character.username}"
          :group_path -> Bonfire.Common.URIs.path(group)
        end

      conn()
      |> visit(path)
      |> wait_async()
      # the not-found page, reached on purpose: `mounted/3` refuses a group this visitor may not see, and says so
      |> assert_has("#error-headline", text: "Not found")
      # not the crash `GroupLive.mount/3` used to hit by reading a `:category` that was never assigned
      |> refute_has("#error-headline", text: "unexpected")
      |> refute_has("[data-id=feed]")
      |> refute_has("[data-id=group]", text: "members only talk")
    end
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
