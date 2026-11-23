defmodule Bonfire.UI.Groups.GroupAppearanceTest do
  @moduledoc "A group's colour and icon, picked in its identity settings, and the hero band that shows its colour only when one is set."
  use Bonfire.UI.Groups.ConnCase, async: false
  @moduletag :ui

  alias Bonfire.Classify.Appearance
  alias Bonfire.Classify.Categories
  alias Bonfire.Classify.Simulate

  setup do
    account = fake_account!()
    owner = fake_user!(account)

    group =
      Simulate.fake_group!(owner, %{
        name: Faker.Company.name(),
        membership: "on_request",
        visibility: "nonfederated"
      })

    {:ok, account: account, owner: owner, group: group, conn: conn(user: owner, account: account)}
  end

  defp reload(group) do
    {:ok, group} = Categories.get(id(group), [:default, skip_boundary_check: true])
    Appearance.preload(group)
  end

  test "the owner picks a colour and an icon in the identity settings, and resets them", %{
    conn: conn,
    group: group
  } do
    session =
      conn
      |> visit("/&#{group.character.username}/settings")
      |> click_button("#group_settings_identity_open", "Edit")
      |> assert_has("#modal [data-role=appearance_picker]")
      |> click_button("#modal [data-swatch=teal]", "teal")
      |> assert_has("#modal [data-swatch=teal][aria-pressed=true]")
      # the picker's own flash (a component does not get the page's)
      |> assert_has("#modal [data-role=appearance_picker] [role=status]", text: "Saved")
      |> click_button("#modal [data-icon='ph:users-three-fill']", "users three")
      |> assert_has("#modal [data-icon='ph:users-three-fill'][aria-pressed=true]")

    assert Appearance.own_colour(reload(group)) == "teal"
    assert Appearance.icon(reload(group)) == "ph:users-three-fill"

    session
    |> click_button("#modal [data-role=reset_colour]", "Reset")
    |> click_button("#modal [data-role=reset_icon]", "Reset")

    assert Appearance.own_colour(reload(group)) == nil
    assert Appearance.icon(reload(group)) == nil
  end

  test "an instance admin who created a public group picks its colour and icon in the identity settings" do
    account = fake_account!()
    admin = fake_admin!(account)

    group =
      Simulate.fake_group!(admin, %{
        name: Faker.Company.name(),
        membership: "open",
        visibility: "global"
      })

    conn(user: admin, account: account)
    |> visit("/&#{group.character.username}/settings")
    |> click_button("#group_settings_identity_open", "Edit")
    |> assert_has("#modal [data-role=appearance_picker]")
    |> click_button("#modal [data-swatch=teal]", "teal")
    |> assert_has("#modal [data-role=appearance_picker] [role=status]", text: "Saved")
    |> refute_has("#modal [data-role=appearance_picker] [role=alert]")
    |> click_button("#modal [data-icon='ph:users-three-fill']", "users three")
    |> assert_has("#modal [data-role=appearance_picker] [role=status]", text: "Saved")

    assert Appearance.own_colour(reload(group)) == "teal"
    assert Appearance.icon(reload(group)) == "ph:users-three-fill"
  end

  test "an instance admin who did not create the group picks its colour, as they edit its identity",
       %{
         group: group
       } do
    account = fake_account!()
    admin = fake_admin!(account)

    conn(user: admin, account: account)
    |> visit("/&#{group.character.username}/settings")
    |> click_button("#group_settings_identity_open", "Edit")
    |> assert_has("#modal [data-role=appearance_picker]")
    |> click_button("#modal [data-swatch=teal]", "teal")
    |> assert_has("#modal [data-role=appearance_picker] [role=status]", text: "Saved")
    |> refute_has("#modal [data-role=appearance_picker] [role=alert]")

    assert Appearance.own_colour(reload(group)) == "teal"
  end

  test "the hero shows the picked icon with no uploaded image, and the default tile with neither",
       %{
         conn: conn,
         owner: owner,
         group: group
       } do
    conn
    |> visit("/&#{group.character.username}")
    |> refute_has("[data-role=group-hero-icon]")

    {:ok, _} = Appearance.set_icon(group, "ph:users-three-fill", current_user: owner)

    conn
    |> visit("/&#{group.character.username}")
    |> assert_has("[data-role=group-hero-icon] [iconify='ph:users-three-fill']")
  end

  # uploads are resized with vips, which CI doesn't have
  @tag Bonfire.Common.RuntimeConfig.skip_in_ci()
  test "the hero shows the uploaded image, not the picked icon", %{
    conn: conn,
    owner: owner,
    group: group
  } do
    {:ok, _} = Appearance.set_icon(group, "ph:users-three-fill", current_user: owner)

    conn
    |> visit("/&#{group.character.username}")
    |> assert_has("[data-role=group-hero-icon]")

    {:ok, avatar} =
      Bonfire.Files.Simulation.fake_upload(
        Bonfire.Files.Simulation.image_file(),
        Bonfire.Files.IconUploader,
        owner
      )

    {:ok, _} =
      Categories.update(owner, group, %{"profile" => %{"icon" => avatar, "icon_id" => avatar.id}})

    conn
    |> visit("/&#{group.character.username}")
    |> assert_has("[data-role=group-hero-avatar]")
    |> refute_has("[data-role=group-hero-icon]")
  end

  test "the hero has a band in the group's colour only when one is set", %{
    conn: conn,
    owner: owner,
    group: group
  } do
    conn
    |> visit("/&#{group.character.username}")
    |> refute_has("[data-role=group_hero_band]")

    {:ok, _} = Appearance.set_colour(group, "teal", current_user: owner)

    conn
    |> visit("/&#{group.character.username}")
    |> assert_has("[data-role=group_hero_band].topic-teal")
  end
end
