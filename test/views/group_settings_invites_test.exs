defmodule Bonfire.UI.Groups.GroupSettingsInvitesTest do
  @moduledoc "The instance's invites are shown in a group's settings only to someone who may invite to the instance. A group admin without that right sees no invites section, and no error."
  use Bonfire.UI.Groups.ConnCase, async: false
  @moduletag :ui

  alias Bonfire.Classify.Simulate

  defp group_for(owner) do
    Simulate.fake_group!(owner, %{
      name: Faker.Company.name(),
      membership: "open",
      visibility: "global"
    })
  end

  test "a group admin who can't invite to the instance gets no invites section and no error" do
    account = fake_account!()
    owner = fake_user!(account)
    refute Bonfire.Boundaries.can?(owner, :invite, :instance)
    group = group_for(owner)

    conn(user: owner, account: account)
    |> visit("/&#{group.character.username}/settings/invites")
    |> refute_has("#bonfire_invites")
    |> refute_has("#invites_list")
    |> refute_has("[role=alert]", text: "permission")
  end

  test "an instance admin sees the instance's invites in the group's settings (control)" do
    account = fake_account!()
    admin = fake_admin!(account)
    group = group_for(admin)

    {:ok, _invite} =
      Bonfire.Invite.Links.create(admin, %{"max_uses" => 1, "max_days_valid" => 2})

    conn(user: admin, account: account)
    |> visit("/&#{group.character.username}/settings/invites")
    |> assert_has("#invites_list tr", count: 1)
  end
end
