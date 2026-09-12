if Bonfire.Common.Extend.extension_enabled?(:bonfire_ui_groups) do
  defmodule Bonfire.UI.Groups.MembershipPaginationTest do
    @moduledoc """
    UI coverage for group membership page pagination and correct member count badge.
    The default test pagination limit is 2 (config/test.exs), so 3+ members forces a second page.
    """
    use Bonfire.UI.Groups.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
    @moduletag :ui

    use Bonfire.Common.Utils
    alias Bonfire.Classify.Categories
    alias Bonfire.Classify.Simulate

    setup do
      Process.put(:federating, false)
      account = fake_account!()
      admin = fake_user!(account)
      conn = conn(user: admin, account: account)
      {:ok, conn: conn, account: account, admin: admin}
    end

    defp members_path(group), do: "/&#{group.character.username}?tab=members"

    test "member count badge shows DB total, not just loaded page slice", %{
      conn: conn,
      admin: admin
    } do
      group =
        Simulate.fake_group!(admin, %{name: "Count Badge Group", membership: "local:members"})

      # test limit is 2; add 3 extra members so page 1 loads only 2 of them
      members = for _ <- 1..3, do: fake_user!(fake_account!())
      for m <- members, do: {:ok, _} = Categories.join_group(m, group, skip_boundary_check: true)

      total = Categories.members_count(group)

      conn
      |> visit(members_path(group))
      |> wait_async()
      |> assert_has("#members-directory-count", text: to_string(total), exact: true)
    end

    test "members tab shows Load more button when members exceed page limit", %{
      conn: conn,
      admin: admin
    } do
      group =
        Simulate.fake_group!(admin, %{name: "Paginate Group", membership: "local:members"})

      members = for _ <- 1..3, do: fake_user!(fake_account!())
      for m <- members, do: {:ok, _} = Categories.join_group(m, group, skip_boundary_check: true)

      conn
      |> visit(members_path(group))
      |> wait_async()
      |> assert_has("[data-id=load_more]")
    end

    test "clicking Load more appends the next page of members", %{conn: conn, admin: admin} do
      group =
        Simulate.fake_group!(admin, %{name: "Paginate Load Group", membership: "local:members"})

      m1 = fake_user!(fake_account!(), %{name: "Alice Alpha"})
      m2 = fake_user!(fake_account!(), %{name: "Bob Beta"})
      m3 = fake_user!(fake_account!(), %{name: "Cara Gamma"})

      for m <- [m1, m2, m3],
          do: {:ok, _} = Categories.join_group(m, group, skip_boundary_check: true)

      conn
      |> visit(members_path(group))
      |> wait_async()
      |> click_button("[data-id=load_more]", "Load more")
      |> assert_has("#group-member-directory", text: "Alice Alpha")
      |> assert_has("#group-member-directory", text: "Bob Beta")
      |> assert_has("#group-member-directory", text: "Cara Gamma")
    end
  end
end
