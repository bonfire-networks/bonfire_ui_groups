defmodule Bonfire.UI.Groups.GroupsDefaultViewTest do
  @moduledoc """
  Which view `/groups` opens on: a member of any group gets the feed of their groups, everyone else, guests included, the directory. The "Groups page opens on" setting wins over that choice. The URL stays `/groups`, so a bookmark keeps following the setting.
  """
  use Bonfire.UI.Groups.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  alias Bonfire.Classify.Categories
  alias Bonfire.Classify.Simulate
  alias Bonfire.Common.Settings

  # open and public, since a group made with no dimensions reviews joins and would leave the join a request
  @open_group %{
    membership: "open",
    visibility: "global",
    participation: "anyone",
    default_content_visibility: "public"
  }

  setup do
    Process.put([:bonfire, :feed_live_update_many_preload_mode], :inline)
    Process.put(:federating, false)

    owner = fake_user!()
    group = Simulate.fake_group!(owner, Map.put(@open_group, :name, "Default View Group"))
    Simulate.fake_post_in_group!(owner, group, "<p>A post in the default view group</p>")

    member_account = fake_account!()
    member = fake_user!(member_account)
    {:ok, _} = Categories.join_group(member, group)

    loner_account = fake_account!()
    loner = fake_user!(loner_account)

    %{
      group: group,
      member: member,
      member_account: member_account,
      loner: loner,
      loner_account: loner_account
    }
  end

  defp assert_feed_view(session) do
    session
    |> wait_async()
    |> assert_has("[data-id=feed] article", text: "A post in the default view group")
    |> assert_has("[data-id=feed] [data-role=published_in]", text: "Default View Group")
    |> refute_has("#group-discovery-grid")
  end

  defp assert_directory_view(session, group) do
    session
    |> assert_has("#group-discovery-grid #group-preview-#{id(group)}")
    |> refute_has("[data-id=feed]")
  end

  defp with_setting(user, value) do
    current_user(Settings.put([Bonfire.UI.Groups, :default_view], value, current_user: user))
  end

  test "a member of a group opens on the feed of their groups", ctx do
    conn(user: ctx.member, account: ctx.member_account)
    |> visit("/groups")
    |> assert_feed_view()
    |> assert_path("/groups")
  end

  test "a user in no group opens on the directory", ctx do
    conn(user: ctx.loner, account: ctx.loner_account)
    |> visit("/groups")
    |> assert_directory_view(ctx.group)
  end

  test "a guest opens on the directory", ctx do
    conn()
    |> visit("/groups")
    |> assert_directory_view(ctx.group)
  end

  test "following a group without joining it opens on the directory", ctx do
    {:ok, _} = Categories.follow_group(ctx.loner, ctx.group)
    refute Categories.member?(ctx.loner, ctx.group), "control: following made no member"

    conn(user: ctx.loner, account: ctx.loner_account)
    |> visit("/groups")
    |> assert_directory_view(ctx.group)
  end

  test "a member whose only group is archived opens on the directory", ctx do
    own = Simulate.fake_group!(ctx.loner, Map.put(@open_group, :name, "Shelved Own Group"))
    assert Categories.member?(ctx.loner, own), "control: a group's creator is its member"
    {:ok, _} = Categories.soft_delete(own, ctx.loner)

    conn(user: ctx.loner, account: ctx.loner_account)
    |> visit("/groups")
    |> assert_directory_view(ctx.group)
  end

  test "each setting value wins over the automatic choice", ctx do
    conn(user: with_setting(ctx.member, :discover), account: ctx.member_account)
    |> visit("/groups")
    |> assert_directory_view(ctx.group)
    |> assert_path("/groups")

    conn(user: with_setting(ctx.loner, :feed_all), account: ctx.loner_account)
    |> visit("/groups")
    |> assert_feed_view()
    |> assert_path("/groups")

    conn(user: with_setting(ctx.member, :automatic), account: ctx.member_account)
    |> visit("/groups")
    |> assert_feed_view()

    conn(user: with_setting(ctx.loner, :automatic), account: ctx.loner_account)
    |> visit("/groups")
    |> assert_directory_view(ctx.group)
  end

  test "the setting is on the user's groups settings page", ctx do
    conn(user: ctx.loner, account: ctx.loner_account)
    |> visit("/settings/user/bonfire_ui_groups")
    |> assert_has("*", text: "Groups page opens on")
    |> PhoenixTest.select("Groups page opens on",
      option: "Latest activities from all known groups"
    )

    conn(user: ctx.loner, account: ctx.loner_account)
    |> visit("/groups")
    |> assert_feed_view()
  end
end
