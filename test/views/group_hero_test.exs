defmodule Bonfire.UI.Groups.GroupHeroTest do
  @moduledoc """
  The group header (`Bonfire.UI.Groups.GroupHeroLive`): the same header for everyone, where only the actions differ. Visitors get Join and follow; members get their membership as a status, the bell, and Leave in the ⋯ menu. Which actions show depends on the viewer's membership, not on `view_mode`: a non-member of an open public group can read everything (`:full`) and still needs Join.
  """
  use Bonfire.UI.Groups.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  doctest Bonfire.UI.Groups.GroupHeroLive
  doctest Bonfire.UI.Groups.GroupHeroActionsLive

  alias Bonfire.Classify.Simulate
  alias Bonfire.Classify.Categories

  @hero "[data-id=group_hero]"
  @visitor "[data-id=group_hero][data-variant=visitor]"
  @member "[data-id=group_hero][data-variant=member]"

  setup do
    creator_account = fake_account!()
    creator = fake_user!(creator_account)

    group =
      Simulate.fake_group!(creator, %{
        name: "Reading together",
        membership: "open",
        visibility: "global",
        participation: "group_members",
        default_content_visibility: "public"
      })

    %{creator: creator, creator_account: creator_account, group: group}
  end

  defp group_path(group), do: "/group/#{group.character.username}"

  defp signed_in do
    account = fake_account!()
    user = fake_user!(account)
    {user, conn(user: user, account: account)}
  end

  describe "visitors" do
    test "a guest is offered Join and follow in the header", %{group: group} do
      conn()
      |> visit(group_path(group))
      |> assert_has(@visitor)
      |> assert_has("#{@hero} h1", text: "Reading together")
      |> assert_has("#{@hero} [data-role=group-hero-members]", text: "1 member")
      |> assert_has("#{@hero} [data-role=group-hero-actions]", text: "Join")
      |> assert_has(
        "#{@hero} [data-role=group-hero-actions] [aria-label='Follow without joining']"
      )
      |> refute_has(@member)
    end

    # `view_mode` is `:full` here, so it can't be what picks the header
    test "a signed-in non-member of an open public group is offered Join", %{group: group} do
      {_user, conn} = signed_in()

      conn
      |> visit(group_path(group))
      |> assert_has(@visitor)
      |> refute_has(@member)
    end

    test "the address is shown in full and copyable", %{group: group} do
      address = Bonfire.Me.Characters.display_username(group, true)
      [handle, host] = String.split(address, "@", parts: 2)

      # the visible text may break before the host (`<wbr>`), so the handle and the host are checked apart; the copied value is the whole address
      conn()
      |> visit(group_path(group))
      |> assert_has(
        "#{@hero} [data-role=group-address][phx-hook=Copy][data-clipboard-text='#{address}']",
        text: handle
      )
      |> assert_has("#{@hero} [data-role=group-address]", text: "@#{host}")
    end

    # the same tile as the sidebar's, so a group looks the same in both
    test "a group without an avatar shows its initial", %{group: group} do
      conn()
      |> visit(group_path(group))
      |> assert_has("#{@hero} [data-role=group_tile]", text: "R")
      |> refute_has("#{@hero} [data-role=group_preset_icon]")
    end
  end

  describe "a pending request" do
    setup %{creator: creator} do
      group =
        Simulate.fake_group!(creator, %{
          name: "Ask first",
          membership: "on_request",
          visibility: "global",
          participation: "group_members",
          default_content_visibility: "public"
        })

      %{group: group}
    end

    test "a non-member is offered Request to join", %{group: group} do
      {_user, conn} = signed_in()

      conn
      |> visit(group_path(group))
      |> assert_has("#{@visitor} [data-role=group-hero-actions]", text: "Request to join")
    end

    test "someone who asked sees Pending, not the member actions", %{group: group} do
      {user, conn} = signed_in()
      assert {:ok, %{requested: true}} = Categories.join_group(user, group)

      conn
      |> visit(group_path(group))
      |> assert_has("#{@visitor} [data-role=group-hero-actions]", text: "Pending")
      |> refute_has(@member)
    end
  end

  describe "members" do
    test "a member sees Joined as a status, and Leave in ⋯", %{group: group} do
      {user, conn} = signed_in()
      {:ok, _} = Categories.join_group(user, group)

      conn
      |> visit(group_path(group))
      |> assert_has(@member)
      |> assert_has("#{@hero} [data-role=group-hero-status]", text: "Joined")
      |> refute_has("#{@hero} [data-role=group-hero-actions] button", text: "Joined")
      |> assert_has("#{@hero} [data-role=group-hero-more]", text: "Leave group")
      |> refute_has(@visitor)
    end

    test "the group's moderator sees Moderator as the status, and a settings gear", %{
      group: group,
      creator: creator,
      creator_account: account
    } do
      conn(user: creator, account: account)
      |> visit(group_path(group))
      |> assert_has("#{@member} [data-role=group-hero-status]", text: "Moderator")
      |> assert_has("#{@hero} [data-role=group-hero-actions] a[aria-label='Manage']")
      |> refute_has("#{@hero} [data-role=group-hero-more]", text: "Group settings")
    end

    # `{:refresh_membership, id}` re-runs `membership_assigns`, which carries the viewer's membership
    test "joining switches to the member actions without a reload", %{group: group} do
      {_user, conn} = signed_in()

      {:ok, view, _html} = live(conn, group_path(group))
      assert has_element?(view, @visitor)

      view
      |> element("#{@hero} [data-role=group-hero-actions] button", "Join")
      |> render_click()

      assert has_element?(view, @member)
      assert has_element?(view, "#{@hero} [data-role=group-hero-status]", "Joined")
    end

    # a sub-group is its own group (by type, not by having a parent), so the refresh after joining must match the sub-group, not its parent
    test "joining a sub-group switches to the member actions without a reload", %{
      creator: creator,
      group: group
    } do
      subgroup =
        Simulate.fake_category!(creator, group, %{
          name: "Night runs",
          type: :group,
          membership: "open",
          visibility: "global"
        })

      {_user, conn} = signed_in()

      {:ok, view, _html} = live(conn, group_path(subgroup))
      assert has_element?(view, "#{@hero} h1", "Night runs")
      assert has_element?(view, @visitor)

      view
      |> element("#{@hero} [data-role=group-hero-actions] button", "Join")
      |> render_click()

      assert has_element?(view, "#{@hero} [data-role=group-hero-status]", "Joined")
    end

    # the page header is the sticky bar (back, and a guest's sign-in actions), so it stays above the group's own header
    test "the page header stays, for guests and members", %{group: group} do
      {_user, conn} = signed_in()

      for session <- [conn(), conn] do
        session
        |> visit(group_path(group))
        |> assert_has("[data-role=page_header_bar]")
      end
    end

    # the page reads the pin state once, so a toggle has to flip its own label, without a reload
    # joining pins the group to the member's sidebar, so the toggle starts from pinned
    test "unpinning from my sidebar in ⋯ flips the menu's label", %{group: group} do
      {user, conn} = signed_in()
      {:ok, _} = Categories.join_group(user, group)
      assert Bonfire.Social.Pins.pinned?(user, group), "control: joining pinned it"

      conn
      |> visit(group_path(group))
      |> click_button(
        "#{@hero} [data-role=group-hero-more] [data-role=open_modal]",
        "Unpin from sidebar"
      )
      |> click_button("#modal button[phx-value-direction=down]", "Unpin from sidebar")
      |> assert_has("#{@hero} [data-role=group-hero-more]", text: "Pin to sidebar")

      refute Bonfire.Social.Pins.pinned?(user, group)
    end

    test "an admin pinning to everyone's sidebar from ⋯ flips the menu's label", %{group: group} do
      account = fake_account!()
      {:ok, admin} = Bonfire.Me.Users.make_admin(fake_user!(account))

      conn(user: admin, account: account)
      |> visit(group_path(group))
      |> click_button("#{@hero} [data-role=instance_pin_toggle]", "Pin to everyone's sidebar")
      |> assert_has("#{@hero} [data-role=instance_pin_toggle]",
        text: "Unpin from everyone's sidebar"
      )
      # an instance-pinned group shows no personal pin row at all
      |> refute_has("#{@hero} [data-role=group-hero-sidebar-pin]")
      |> refute_has("#{@hero} [data-role=group-hero-more]", text: "Pin to sidebar")
      |> refute_has("#{@hero} [data-role=group-hero-more]", text: "Unpin from sidebar")

      assert Bonfire.Social.Pins.pinned?(:instance, group)
    end

    # another admin, another tab or an API client: the page hears of it from `Pins`
    test "⋯ drops the personal pin row when an instance pin is made elsewhere on an open page", %{
      group: group
    } do
      {user, conn} = signed_in()
      {:ok, _} = Categories.join_group(user, group)
      admin = fake_admin!(fake_account!())

      session =
        conn
        |> visit(group_path(group))
        |> assert_has("#{@hero} [data-role=group-hero-sidebar-pin]", text: "Unpin from sidebar")

      {:ok, _} = Bonfire.Social.Pins.pin(admin, group, :instance)

      refute_has(session, "#{@hero} [data-role=group-hero-sidebar-pin]", timeout: 1_000)
    end

    test "the group's settings replace the header", %{
      group: group,
      creator: creator,
      creator_account: account
    } do
      conn(user: creator, account: account)
      |> visit(group_path(group) <> "/settings")
      |> refute_has(@hero)
    end

    # following without joining doesn't make someone a member, so the facepile comes from the members circle, not followers
    test "the facepile shows members, not people who only follow", %{group: group} do
      member_account = fake_account!()
      member = fake_user!(member_account, %{name: "Mara Member"})
      {:ok, _} = Categories.join_group(member, group)

      follower = fake_user!(fake_account!(), %{name: "Felix Follower"})
      {:ok, _} = Bonfire.Social.Graph.Follows.follow(follower, group)

      conn(user: member, account: member_account)
      |> visit(group_path(group))
      |> assert_has("#{@hero} [data-role=group-hero-facepile] [title='Mara Member']")
      |> refute_has("#{@hero} [data-role=group-hero-facepile] [title='Felix Follower']")
      |> assert_has("#{@hero} [data-role=group-hero-members]", text: "2 members")
    end
  end
end
