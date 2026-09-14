defmodule Bonfire.UI.Groups.GroupMembersTest do
  use Bonfire.UI.Groups.ConnCase, async: false
  @moduletag :ui

  alias Bonfire.Classify.Categories

  setup do
    Process.put(:federating, false)
    account = fake_account!()
    me = fake_user!(account)

    {:ok, group} =
      Categories.create(
        me,
        %{
          name: Faker.Lorem.sentence(),
          username: "directory_#{System.unique_integer([:positive])}",
          type: :group,
          membership: "open",
          visibility: "global"
        },
        true
      )

    %{account: account, me: me, group: group}
  end

  test "directory combines membership and moderator roles without duplicate people", %{
    account: account,
    me: me,
    group: group
  } do
    member = fake_user!(fake_account!())
    {:ok, _} = Categories.join_and_follow_group(member, group)

    conn(user: me, account: account)
    |> visit("/group/#{group.character.username}/members")
    |> refute_has("[data-role=group-sidebar-moderators]")
    |> assert_has("#members-directory-count", text: "2")
    |> assert_has("#group-member-directory li", count: 2)
    |> assert_has("#directory-member-#{me.id}", text: "Moderator")
    |> assert_has("#directory-member-#{me.id}", text: "You")
    |> assert_has("#directory-member-#{member.id}", text: "Member")
    |> click_button("Moderators")
    |> assert_has("#group-member-directory li", count: 1)
    |> refute_has("#directory-member-#{member.id}")
    |> assert_has("#members-directory-count", text: "2")
    |> click_button("Everyone")
    |> assert_has("#directory-member-#{member.id}")
    |> click_link("#members-parent-link", group.profile.name)
    |> assert_path("/group/#{group.character.username}")
  end

  test "a moderator outside the member list still appears once" do
    moderator = fake_user!(fake_account!())
    member = fake_user!(fake_account!())
    entries = Bonfire.UI.Groups.GroupMembersLive.directory_entries([member], [moderator])
    assert Enum.map(entries, & &1.id) == [moderator.id, member.id]
    assert Enum.map(entries, & &1.moderator?) == [true, false]

    assert length(
             Bonfire.UI.Groups.GroupMembersLive.directory_entries([moderator, member], [moderator])
           ) == 2
  end

  test "search clearing restores loaded people and leaves pagination available", %{
    account: account,
    me: me,
    group: group
  } do
    for _ <- 1..3 do
      {:ok, _} = Categories.join_and_follow_group(fake_user!(fake_account!()), group)
    end

    conn(user: me, account: account)
    |> visit("/group/#{group.character.username}/members")
    |> fill_in("Search members", with: "no-such-person-xyz")
    |> assert_has("#member-directory-empty")
    |> assert_has("[data-id=load_more]")
    |> click_button("Clear search")
    |> refute_has("#member-directory-empty")
    |> click_button("[data-id=load_more]", "Load more")
    |> assert_has("#group-member-directory li", count: 4)
    |> assert_has("#members-directory-count", text: "4")
  end
end
