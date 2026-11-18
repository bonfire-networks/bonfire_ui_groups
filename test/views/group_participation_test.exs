defmodule Bonfire.UI.Groups.GroupParticipationTest do
  use Bonfire.UI.Groups.ConnCase, async: false

  alias Bonfire.Classify.Categories
  alias Bonfire.Social.Graph.Follows

  @joined "[data-id=group_hero][data-variant=member] [data-role=group-hero-status]"

  # the group's Join button (or an element of its dialogs, by `suffix`)
  defp join_btn(group, suffix \\ nil),
    do: component_selector(Bonfire.Classify.Web.JoinButtonLive, id(group), suffix: suffix)

  # the hero's own Follow button, not the Join button's follow toggle for the same group
  defp hero_follow(group),
    do:
      component_selector(Bonfire.UI.Social.Graph.FollowButtonLive, id(group),
        parent: Bonfire.UI.Groups.GroupHeroActionsLive
      )

  test "separate membership and feed controls preserve independent states" do
    Process.put(:federating, false)
    account = fake_account!()
    user = fake_user!(account)
    creator = fake_user!(account)

    {:ok, group} =
      Categories.create(
        creator,
        %{
          name: Faker.Lorem.sentence(),
          username: "participation_#{System.unique_integer([:positive])}",
          type: :group,
          membership: "open",
          visibility: "global"
        },
        true
      )

    {:ok, _} = Categories.join_and_follow_group(user, group)
    path = "/&#{group.character.username}"

    session =
      conn(user: user, account: account)
      |> visit(path)
      |> assert_has(@joined, text: "Joined")
      |> assert_has(
        "button.tooltip[data-tip='Unfollow group']#{hero_follow(group)}.text-primary[aria-pressed='true']"
      )
      |> assert_has("#{hero_follow(group)} [iconify='ph:rss']")
      |> click_button("button#{hero_follow(group)}[data-id=unfollow]", "")
      |> assert_has(@joined, text: "Joined")
      |> assert_has(
        "button.tooltip[data-tip='Follow group']#{hero_follow(group)}.text-muted[aria-pressed='false']"
      )

    refute Follows.following?(user, group)

    session =
      session
      |> assert_has(@joined, text: "Joined")
      |> click_button("#group_hero_leave_#{group.id}", "Leave group")
      # leaving asks first, and staying changes nothing; the hero's Leave is not a Join button, so its dialog is named by the group
      |> click_button("#group_#{group.id}-stay", "Stay")
      |> assert_has(@joined, text: "Joined")
      |> click_button("#group_hero_leave_#{group.id}", "Leave group")
      |> click_button("#group_#{group.id}-leave", "Leave group")
      |> assert_has(join_btn(group), text: "Join")
      |> click_button("button#{hero_follow(group)}[data-id=follow]", "")
      |> assert_has(
        "button.tooltip[data-tip='Unfollow group']#{hero_follow(group)}.text-primary[aria-pressed='true']"
      )

    assert Follows.following?(user, group)
    refute Map.get(Categories.member_of_groups?(user, [group.id]), group.id, false)

    session =
      session
      |> click_button(join_btn(group), "Join")
      |> assert_has(@joined, text: "Joined")

    assert Follows.following?(user, group)
    assert Map.get(Categories.member_of_groups?(user, [group.id]), group.id, false)

    session
    |> click_button("#group_hero_leave_#{group.id}", "Leave group")
    |> click_button("#group_#{group.id}-leave", "Leave group")
    |> assert_has(join_btn(group), text: "Join")
    |> assert_has("#{hero_follow(group)}[aria-pressed='true']")

    assert Follows.following?(user, group)
    refute Map.get(Categories.member_of_groups?(user, [group.id]), group.id, false)
  end

  test "join requests can be cancelled from the group button" do
    Process.put(:federating, false)
    account = fake_account!()
    user = fake_user!(account)
    creator = fake_user!(account)

    {:ok, group} =
      Categories.create(
        creator,
        %{
          name: Faker.Lorem.sentence(),
          username: "request_#{System.unique_integer([:positive])}",
          type: :group,
          membership: "on_request",
          visibility: "global"
        },
        true
      )

    session =
      conn(user: user, account: account)
      |> visit("/&#{group.character.username}")
      |> click_button(join_btn(group), "Request to join")
      |> assert_has(join_btn(group), text: "Pending")

    # a join request is typed by the `:join` verb rather than standing in as a pending Follow, which is what lets someone hold one while already subscribed to the same group
    assert requested_to_join?(user, group)

    session
    |> click_button(join_btn(group), "Pending")
    |> assert_has("[role=dialog]", text: "Withdraw join request?")
    |> click_button(join_btn(group, "-keep-request"), "Keep request")
    |> refute_has(join_btn(group, "-withdrawal"))
    |> assert_has(join_btn(group), text: "Pending")
    |> click_button(join_btn(group), "Pending")
    |> click_button(join_btn(group, "-withdraw-request"), "Withdraw request")
    |> assert_has(join_btn(group), text: "Request to join")
    |> refute_has("[data-id=flash_error]")

    refute requested_to_join?(user, group)
    refute Map.get(Categories.member_of_groups?(user, [group.id]), group.id, false)
  end

  defp requested_to_join?(user, group),
    do:
      Bonfire.Social.Requests.requested?(
        user,
        Bonfire.Boundaries.Verbs.get_id!(:join),
        group
      )
end
