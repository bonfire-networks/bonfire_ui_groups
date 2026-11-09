defmodule Bonfire.UI.Groups.GroupHeroCompactTest do
  @moduledoc """
  Compact hero and header toggle for members, full hero for visitors.
  """
  use Bonfire.UI.Groups.ConnCase, async: false
  @moduletag :ui

  alias Bonfire.Classify.Categories

  @compact_hero "[data-id=group_hero][data-compact]"
  @full_hero "[data-id=group_hero]:not([data-compact])"
  @toggle "[data-role=group-hero-toggle]"
  @header_avatar "[data-role=page_header_icon]"

  setup do
    owner = fake_user!()
    account = fake_account!()
    user = fake_user!(account)

    group =
      Bonfire.Classify.Simulate.fake_group!(owner, %{
        name: "Compact club",
        membership: "open",
        visibility: "global"
      })

    %{group: group, user: user, account: account}
  end

  test "a member sees the compact hero, with the group's avatar and the toggle in the page header",
       context do
    assert {:ok, _} = Categories.join_and_follow_group(context.user, context.group)

    conn(user: context.user, account: context.account)
    |> visit(Bonfire.Common.URIs.path(context.group))
    |> wait_async()
    |> assert_has_or_open_browser(@compact_hero)
    |> assert_has(@header_avatar)
    |> assert_has("#{@toggle}[aria-controls='group_hero-#{context.group.id}-member']")
  end

  test "a visitor sees the full hero, with no avatar or toggle in the page header", context do
    conn(user: context.user, account: context.account)
    |> visit(Bonfire.Common.URIs.path(context.group))
    |> wait_async()
    |> assert_has_or_open_browser(@full_hero)
    |> refute_has(@header_avatar)
    |> refute_has(@toggle)
  end

  test "joining swaps the hero to compact and adds the toggle, without a reload", context do
    conn(user: context.user, account: context.account)
    |> visit(Bonfire.Common.URIs.path(context.group))
    |> wait_async()
    |> refute_has(@toggle)
    |> click_button("button[id^=join_btn_]", "Join")
    |> wait_async()
    |> assert_has_or_open_browser(@compact_hero)
    |> assert_has(@toggle)
  end

  test "leaving restores the full hero and removes the toggle, without a reload", context do
    assert {:ok, _} = Categories.join_and_follow_group(context.user, context.group)

    conn(user: context.user, account: context.account)
    |> visit(Bonfire.Common.URIs.path(context.group))
    |> wait_async()
    |> assert_has(@toggle)
    |> click_button("#group_hero_leave_#{context.group.id}", "Leave group")
    |> click_button("#join_btn_#{context.group.id}-leave", "Leave group")
    |> wait_async()
    |> assert_has_or_open_browser(@full_hero)
    |> refute_has(@toggle)
    |> refute_has(@header_avatar)
  end

  test "the group's settings show no avatar or toggle in the page header, for its moderator",
       context do
    # the creator moderates, so settings opens
    group =
      Bonfire.Classify.Simulate.fake_group!(context.user, %{
        name: "Settled club",
        membership: "open",
        visibility: "global"
      })

    conn(user: context.user, account: context.account)
    |> visit(Bonfire.Common.URIs.path(group) <> "/settings")
    |> wait_async()
    |> refute_has("[data-id=group_hero]")
    |> refute_has(@toggle)
    |> refute_has(@header_avatar)
  end
end
