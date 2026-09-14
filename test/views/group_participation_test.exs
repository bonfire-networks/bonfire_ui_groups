defmodule Bonfire.UI.Groups.GroupParticipationTest do
  use Bonfire.UI.Groups.ConnCase, async: false

  alias Bonfire.Classify.Categories
  alias Bonfire.Social.Graph.Follows

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
      |> assert_has("#join_btn_#{group.id}", text: "Joined")
      |> assert_has(
        "div.tooltip[data-tip='Unfollow group'] button#follow_feed_#{group.id}.bg-transparent.text-primary[aria-label='Unfollow group'][aria-pressed='true']"
      )
      |> assert_has("#follow_feed_#{group.id} [iconify='ph:rss']")
      |> click_button("button#follow_feed_#{group.id}[data-id=unfollow]", "")
      |> assert_has("#join_btn_#{group.id}", text: "Joined")
      |> assert_has(
        "div.tooltip[data-tip='Follow group'] button#follow_feed_#{group.id}.bg-transparent.text-muted[aria-label='Follow group'][aria-pressed='false']"
      )

    refute Follows.following?(user, group)

    session =
      session
      |> assert_has("#join_btn_#{group.id}", text: "Joined")
      |> click_button("#join_btn_#{group.id}", "Joined")
      |> assert_has("#join_btn_#{group.id}", text: "Join")
      |> click_button("button#follow_feed_#{group.id}[data-id=follow]", "")
      |> assert_has(
        "div.tooltip[data-tip='Unfollow group'] button#follow_feed_#{group.id}.bg-transparent.text-primary[aria-label='Unfollow group'][aria-pressed='true']"
      )

    assert Follows.following?(user, group)
    refute Map.get(Categories.member_of_groups?(user, [group.id]), group.id, false)

    session =
      session
      |> click_button("#join_btn_#{group.id}", "Join")
      |> assert_has("#join_btn_#{group.id}", text: "Joined")

    assert Follows.following?(user, group)
    assert Map.get(Categories.member_of_groups?(user, [group.id]), group.id, false)

    session
    |> click_button("#join_btn_#{group.id}", "Joined")
    |> assert_has("#join_btn_#{group.id}", text: "Join")
    |> assert_has("#follow_feed_#{group.id}[aria-pressed='true']")

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
      |> click_button("#join_btn_#{group.id}", "Request to join")
      |> assert_has("#join_btn_#{group.id}", text: "Cancel request")

    assert Follows.requested?(user, group)

    session
    |> click_button("#join_btn_#{group.id}", "Cancel request")
    |> assert_has("#join_btn_#{group.id}", text: "Request to join")
    |> refute_has("[data-id=flash_error]")

    refute Follows.requested?(user, group)
    refute Map.get(Categories.member_of_groups?(user, [group.id]), group.id, false)
  end
end
