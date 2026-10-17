defmodule Bonfire.UI.Groups.GroupSettingsOverviewTest do
  use Bonfire.UI.Groups.ConnCase, async: false
  @moduletag :ui

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

  test "only identity uses a dialog; the other settings link to dedicated pages", %{
    conn: conn,
    group: group
  } do
    conn
    |> visit("/&#{group.character.username}/settings")
    |> assert_has("[data-role=page_title]", text: "Group settings")
    # |> open_browser()
    |> refute_has("#inline_composer_placeholder")
    |> assert_has("#settings-group-name", text: group.profile.name)
    |> assert_has("#group-settings-people")
    |> assert_has("#group_settings_access_link", text: "On request")
    |> refute_has("#group_settings_identity_form")
    |> refute_has("#group-settings-overview dialog")
    |> click_button("#group_settings_identity_open", "Edit")
    |> assert_has("#modal [role=dialog] #group_settings_identity_form")
    |> refute_has("#group_settings_boundaries_form")
    |> refute_has("#add_moderator_form")
    # settings keep the group's right sidebar, like its other tabs
    |> refute_has("[data-two-columns]")
    |> assert_has("[data-id=secondary_sidebar_widgets]")
  end

  test "settings pages have working links back to the overview", %{conn: conn, group: group} do
    for {link, label, content} <- [
          {"access", "Access & participation", "#group_settings_boundaries_form"},
          {"rules", "Community rules", "#group-rules-#{id(group)}"},
          {"archive", "Archive group", "#group_settings_archive_button"},
          {"moderators", "Manage moderators", "#add_moderator_form"},
          # the group's inbox, for whoever moderates it (the owner does); it used to be reachable by URL only
          {"moderation", "Moderation", "[data-id=feed]"}
        ] do
      conn
      |> visit("/&#{group.character.username}/settings")
      |> click_link("#group_settings_#{link}_link", label)
      |> assert_has(content)
      |> assert_has("[data-role=page_title]", text: label)
      |> refute_has("#group_settings_back")
      |> refute_has("#group-settings-overview")
      |> click_link("Go back to the previous page")
      |> assert_has("[data-role=page_title]", text: "Group settings")
      |> assert_has("#group-settings-overview")
      |> refute_has("#group-settings-detail")
    end
  end

  test "People starts with five members and loads the rest inline without duplicates", %{
    conn: conn,
    owner: owner,
    group: group
  } do
    members =
      for _ <- 1..6 do
        member = fake_user!(fake_account!())
        {:ok, _} = Categories.add_member(owner, group, id(member), skip_boundary_check: true)
        member
      end

    total = Categories.members_count(group)
    assert total == 7

    session =
      conn
      |> visit("/&#{group.character.username}/settings")
      |> assert_has("#settings-people-heading", text: "7 members")
      |> assert_has("[data-role=settings-person]", count: 5)
      |> click_button("#group_settings_people_more", "Load more")
      |> assert_has("#group-settings-overview")
      |> assert_has("[data-role=settings-person]", count: total)
      |> refute_has("#group_settings_people_more")

    for member <- [owner | members] do
      assert_has(session, "#settings-person-#{id(member)}", count: 1)
    end
  end

  # adding someone directly is for a moderator of the group who also moderates the instance, and only for someone on this instance (`Categories.add_member/4`)
  test "an instance moderator who moderates the group adds a local user from People", %{
    conn: conn,
    owner: owner,
    group: group
  } do
    Bonfire.Me.Fake.instance_moderator!(owner)
    member = fake_user!(fake_account!(), %{name: "zqaddmember"})
    {:ok, _} = Categories.add_member(owner, group, id(member), skip_boundary_check: true)
    candidate = fake_user!(fake_account!(), %{name: "zqaddcandidate"})

    Tesla.Mock.mock(fn env -> ActivityPub.Test.HttpRequestMock.request(env) end)
    remote = Bonfire.Social.Fake.fake_remote_user!()
    remote_name = e(remote, :profile, :name, nil)

    {:ok, view, _html} = live(conn, "/&#{group.character.username}/settings")
    view |> element("#group_settings_people_add_open") |> render_click()
    assert has_element?(view, "#add_member_form")

    ls_id = live_select_simulate_search(view, "#add_member_form", "zqadd")
    assert has_element?(view, "##{ls_id} li", candidate.profile.name), "control: offered"
    refute has_element?(view, "##{ls_id} li", member.profile.name), "already a member"

    ls_id = live_select_simulate_search(view, "#add_member_form", remote_name, ls_id)
    refute has_element?(view, "##{ls_id} li", remote_name), "someone on another instance"

    view
    |> element("#add_member_form")
    |> render_change(%{
      "_target" => ["multi_select", "member_select"],
      "multi_select" => %{"member_select" => Jason.encode!(%{"id" => id(candidate)})}
    })

    assert Categories.member?(candidate, group)
    assert has_element?(view, "#settings-person-#{id(candidate)}"), "shown in People"
  end

  test "a group moderator who doesn't moderate the instance isn't offered Add", %{
    conn: conn,
    group: group
  } do
    conn
    |> visit("/&#{group.character.username}/settings")
    |> assert_has("#group-settings-people")
    |> refute_has("#group_settings_people_add_open")
  end

  test "saving identity updates the overview and the persisted profile", %{
    conn: conn,
    group: group
  } do
    updated_name = Faker.Company.name()

    conn
    |> visit("/&#{group.character.username}/settings")
    |> click_button("#group_settings_identity_open", "Edit")
    |> fill_in("Group name", with: updated_name)
    |> fill_in("Description", with: "Readers sharing ideas together.")
    |> click_button("#group_settings_identity_save", "Save changes")
    |> assert_has("#settings-group-name", text: updated_name)
    |> assert_has("#modal [role=status]", text: "Category updated!")
    |> assert_has("#group-settings-overview p", text: "Readers sharing ideas together.")
    |> click_button("#modal [data-role=close-modal]", "Close")
    |> click_button("#group_settings_identity_open", "Edit")
    # double quotes, since company names can have an apostrophe (eg. "Ziemann-O'Hara")
    |> assert_has(~s(#group_settings_name[value="#{updated_name}"]))
    |> assert_has("#group_settings_summary", text: "Readers sharing ideas together.")

    conn
    |> visit("/&#{group.character.username}/settings")
    |> assert_has("#settings-group-name", text: updated_name)
  end

  # the setup's group is nonfederated, which rightly stays silent, so this one federates
  if Bonfire.Common.Extend.extension_enabled?(:bonfire_federate_activitypub) do
    test "renaming a federated group from its settings tells other instances", %{
      conn: conn,
      owner: owner
    } do
      group =
        Simulate.fake_group!(owner, %{
          membership: "open",
          visibility: "global",
          participation: "anyone",
          default_content_visibility: "public"
        })

      updated_name = Faker.Company.name()

      conn
      |> visit("/&#{group.character.username}/settings")
      |> click_button("#group_settings_identity_open", "Edit")
      |> fill_in("Group name", with: updated_name)
      |> click_button("#group_settings_identity_save", "Save changes")
      |> assert_has("#modal [role=status]", text: "Category updated!")

      assert {:ok, actor} = ActivityPub.Actor.get_cached(pointer: group)

      assert %{data: %{"object" => %{"name" => ^updated_name}}} =
               ActivityPub.Object.get_activity_for_object_ap_id(actor.ap_id, "Update"),
             "the group's followers elsewhere keep its old name"
    end
  end

  test "People search finds members beyond the preview and clears inline", %{
    conn: conn,
    group: group,
    owner: owner
  } do
    members =
      for _ <- 1..6 do
        member = fake_user!(fake_account!())
        {:ok, _} = Categories.add_member(owner, group, id(member), skip_boundary_check: true)
        member
      end

    first_page = Categories.list_members(group, current_user: owner, pagination: [limit: 5])
    loaded_ids = Enum.map(first_page.edges, &id/1)
    target = Enum.find(members, &(id(&1) not in loaded_ids))

    conn
    |> visit("/&#{group.character.username}/settings")
    |> click_button("Search members")
    |> fill_in("Search members", with: String.upcase(target.character.username))
    |> assert_has("#group-settings-overview")
    |> assert_has("[data-role=settings-person]", count: 1)
    |> assert_has("#settings-person-#{id(target)}")
    |> fill_in("Search members", with: "no-such-member-xyz")
    |> assert_has("#group-settings-people", text: "No members match your search.")
    |> refute_has("#group_settings_people_more")
    |> click_button("Clear search")
    |> assert_has("[data-role=settings-person]", count: 5)
    |> assert_has("#group_settings_people_more")
  end

  test "display-name search excludes outsiders and paginates matching members", %{
    conn: conn,
    group: group,
    owner: owner
  } do
    prefix = "ReviewSearch#{System.unique_integer([:positive])}"
    outsider = fake_user!(fake_account!(), %{name: prefix <> " outsider"})

    members =
      for n <- 1..6 do
        member = fake_user!(fake_account!(), %{name: "#{prefix} member #{n}"})
        {:ok, _} = Categories.add_member(owner, group, id(member), skip_boundary_check: true)
        member
      end

    session =
      conn
      |> visit("/&#{group.character.username}/settings")
      |> click_button("Search members")
      |> fill_in("Search members", with: String.downcase(prefix))
      |> assert_has("[data-role=settings-person]", count: 5)
      |> refute_has("#settings-person-#{id(outsider)}")
      |> click_button("Load more")
      |> assert_has("[data-role=settings-person]", count: 6)
      |> refute_has("#group_settings_people_more")

    for member <- members do
      assert_has(session, "#settings-person-#{id(member)}", count: 1)
    end
  end

  test "saving text preserves images changed while the editor was open", %{
    conn: conn,
    group: group,
    owner: owner
  } do
    session =
      conn
      |> visit("/&#{group.character.username}/settings")
      |> click_button("#group_settings_identity_open", "Edit")

    media = Bonfire.Social.Fake.upload_media(:images, owner)

    {:ok, with_images} =
      Categories.update(owner, group, %{profile: %{icon_id: media.id, image_id: media.id}})

    session
    |> fill_in("Description", with: "Saved after image change")
    |> click_button("Save changes")
    |> assert_has("#modal [role=status]", text: "Category updated!")
    |> assert_has(
      "#group-settings-overview img[src='#{Bonfire.Common.Media.avatar_url(with_images)}']"
    )
    |> assert_has(
      "#group-settings-overview img[src='#{Bonfire.Common.Media.banner_url(with_images)}']"
    )

    {:ok, saved} = Categories.get(id(group), [:default, current_user: owner])
    assert saved.profile.icon_id == media.id
    assert saved.profile.image_id == media.id
  end

  test "invalid identity keeps the modal and submitted description", %{conn: conn, group: group} do
    conn
    |> visit("/&#{group.character.username}/settings")
    |> click_button("#group_settings_identity_open", "Edit")
    |> unwrap(fn view ->
      view
      |> Phoenix.LiveViewTest.element("#group_settings_identity_form")
      |> Phoenix.LiveViewTest.render_submit(%{
        "profile" => %{"name" => "", "summary" => "Keep this draft"}
      })
    end)
    |> assert_has("#modal [role=alert]")
    |> assert_has("#group_settings_summary", text: "Keep this draft")
    |> assert_has("#settings-group-name", text: group.profile.name)
  end

  test "settings routes and titles respect extension configuration" do
    Process.put([:bonfire, :ui, :group, :settings, :sections],
      rules: Bonfire.UI.Groups.Settings.GeneralLive
    )

    Process.put([:bonfire, :ui, :group, :settings, :navigation], rules: "Custom rules")

    assert Bonfire.UI.Groups.SettingsLive.tab_component("rules") ==
             Bonfire.UI.Groups.Settings.GeneralLive

    assert Bonfire.UI.Groups.SettingsLive.page_title("rules") == "Custom rules"
  end

  test "ordinary members cannot access editor controls", %{
    account: account,
    owner: owner,
    group: group
  } do
    member = fake_user!(account)
    {:ok, _} = Categories.add_member(owner, group, id(member), skip_boundary_check: true)

    conn(user: member, account: account)
    |> visit("/&#{group.character.username}/settings")
    |> refute_has("#group_settings_identity_open")
    |> refute_has("#group_settings_access_link")
    |> refute_has("#group_settings_archive_button")
  end

  test "a group owner without instance privileges cannot change auto-join", %{
    conn: conn,
    group: group
  } do
    conn
    |> visit("/&#{group.character.username}/settings")
    |> refute_has("#group_settings_instance_link")
    |> refute_has("#group_settings_auto_join_form")

    conn
    |> visit("/&#{group.character.username}/settings/instance")
    |> assert_has("[data-role=page_title]", text: "Instance settings")
    |> refute_has("#group_settings_auto_join_form")
  end
end
