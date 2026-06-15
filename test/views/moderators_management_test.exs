defmodule Bonfire.UI.Groups.ModeratorsManagementTest do
  @moduledoc """
  UI coverage for managing a group's moderators from the General settings tab
  (`Bonfire.UI.Groups.Settings.ModeratorsLive`, embedded in `GeneralLive`):
  promoting a user, demoting one, protecting the owner, and hiding the controls
  from users who can't edit the group's settings.
  """
  use Bonfire.UI.Groups.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  use Bonfire.Common.Utils
  alias Bonfire.Classify.Simulate
  alias Bonfire.Classify.Categories
  alias Bonfire.Boundaries

  setup do
    account = fake_account!()
    admin = fake_user!(account)
    member = fake_user!(account)
    group = Simulate.fake_group!(admin, %{name: "Mod Test Group"})
    conn = conn(user: admin, account: account)
    {:ok, conn: conn, account: account, admin: admin, member: member, group: group}
  end

  defp settings_path(group), do: "/&#{group.character.username}/settings"

  test "admin sees the moderators section with the add-moderator form", %{
    conn: conn,
    group: group
  } do
    conn
    |> visit(settings_path(group))
    |> assert_has("#group-moderators")
    |> assert_has("#add_moderator_form")
  end

  test "admin can promote a user to moderator", %{conn: conn, group: group, member: member} do
    refute Boundaries.can?(member, :mediate, group)

    session = visit(conn, settings_path(group))

    # Simulate the LiveSelect single selection by triggering the form's phx-change
    # with the selected user encoded as JSON (what the JS hook would submit).
    selection =
      Jason.encode!(%{
        "id" => id(member),
        "username" => e(member, :character, :username, "member"),
        "name" => e(member, :profile, :name, "member"),
        "type" => "user"
      })

    # NOTE: the real field name is the MultiselectLive `form_input_name` ("moderator_select"),
    # not the `field` prop — using the real key keeps this test honest vs the live payload.
    session
    |> unwrap(fn view ->
      view
      |> Phoenix.LiveViewTest.element("#add_moderator_form")
      |> Phoenix.LiveViewTest.render_change(%{
        "_target" => ["multi_select", "moderator_select"],
        "multi_select" => %{"moderator_select" => selection}
      })
    end)

    # backend truth: the user is now empowered and listed
    assert Boundaries.can?(member, :mediate, group)
    assert Categories.member_role(member, group) == "moderator"

    # and the row shows up on a fresh render
    conn
    |> visit(settings_path(group))
    |> assert_has("#moderator-#{id(member)}")
  end

  test "admin can remove a moderator", %{conn: conn, group: group, admin: admin, member: member} do
    {:ok, _} = Categories.add_moderator(admin, group, id(member))
    assert Boundaries.can?(member, :mediate, group)

    conn
    |> visit(settings_path(group))
    |> assert_has("#moderator-#{id(member)}")
    |> click_button("#moderator-#{id(member)} [data-role=remove_moderator]", "Remove")

    refute Boundaries.can?(member, :mediate, group)
  end

  test "the group owner cannot be demoted (no Remove button on the custodian)", %{
    conn: conn,
    group: group,
    admin: admin
  } do
    # the creator is listed as a moderator (has :administer → :mediate)
    conn
    |> visit(settings_path(group))
    |> assert_has("#moderator-#{id(admin)}")
    |> refute_has("#moderator-#{id(admin)} [data-role=remove_moderator]")
  end

  test "a plain member cannot reach the General settings tab (no moderator controls)", %{
    account: account,
    group: group,
    admin: admin,
    member: member
  } do
    # make member a plain member (in the members circle) but not a moderator
    {:ok, _} = Categories.add_member(admin, group, id(member))

    member_conn = conn(user: member, account: account)

    member_conn
    |> visit(settings_path(group))
    |> refute_has("#add_moderator_form")
    |> refute_has("[data-role=remove_moderator]")
  end

  test "a non-creator moderator can reach settings and manage moderators", %{
    account: account,
    group: group,
    admin: admin,
    member: member
  } do
    # promote member to moderator (has :mediate but is not the creator/:edit owner)
    {:ok, _} = Categories.add_moderator(admin, group, id(member))
    refute Categories.member_role(member, group) == "admin"

    member_conn = conn(user: member, account: account)

    # the :mediate branch of `ensure_update_allowed` lets them into the General tab + controls
    member_conn
    |> visit(settings_path(group))
    |> assert_has("#group-moderators")
    |> assert_has("#add_moderator_form")
  end

  test "the moderator user-search returns formatted, selectable options", %{account: account} do
    findable = fake_user!(account, %{name: "findmemoderator"})

    # exactly what ModeratorsLive's "live_select_change" handler calls
    results =
      Bonfire.UI.Boundaries.CircleMembersLive.do_results_for_multiselect("findmemoderator",
        local_only: false
      )

    assert results != [], "expected the user search to return at least one option"

    assert Enum.any?(results, fn
             {_label, %{id: id}} -> id == findable.id
             _ -> false
           end)
  end

  test "the moderator live_select search sends options to the dropdown", %{
    conn: conn,
    group: group,
    account: account
  } do
    findable = fake_user!(account, %{name: "findmemoderator"})

    {:ok, view, _html} = live(conn, settings_path(group))

    ls_id = live_select_simulate_search(view, "#group-moderators", "findmemoderator")

    assert has_element?(view, "##{ls_id} li", findable.profile.name)
  end
end
