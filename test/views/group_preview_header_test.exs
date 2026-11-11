defmodule Bonfire.UI.Groups.GroupPreviewHeaderTest do
  @moduledoc """
  A viewer who can only preview a group (`view_mode == :preview`, eg. a local non-member of a group with `nonfederated:preview` visibility) gets the minimal header members already have: the hero folded (`data-compact`), the group's icon and name in the page header, and Join. No banner, description, members or "Who can" widget, and no toggle to expand it. Members of the same group get the full header behind the toggle.
  """
  use Bonfire.UI.Groups.ConnCase, async: false
  @moduletag :ui

  alias Bonfire.Classify.Categories
  alias Bonfire.Classify.Simulate

  @hero "[data-id=group_hero]"
  @compact_hero "[data-id=group_hero][data-compact]"
  @toggle "[data-role=group-hero-toggle]"
  @header_name "[data-role=page_title]"
  @header_icon "[data-role=page_header_icon]"
  @summary "A summary only members should read"

  setup do
    Process.put([:bonfire, :feed_live_update_many_preload_mode], :inline)
    Process.put(:federating, false)

    owner_account = fake_account!()
    owner = fake_user!(owner_account)

    # explicit dimensions (a preview-only group, which `local_community` used to be, and `private_club` still is with `local:preview`): Join "Users of this instance", See "Anyone can preview (but doesn't federate)", Post "Users of this instance", New posts "Users of this instance"
    group =
      Simulate.fake_group!(owner, %{
        name: "Preview header club",
        membership: "local:members",
        visibility: "nonfederated:preview",
        participation: "local:contributors",
        default_content_visibility: "local"
      })

    media = Bonfire.Social.Fake.upload_media(:images, owner)

    {:ok, group} =
      Categories.update(owner, group, %{
        profile: %{icon_id: media.id, image_id: media.id, summary: @summary}
      })

    member_account = fake_account!()
    member = fake_user!(member_account, %{name: "Second Member"})
    assert {:ok, _} = Categories.join_and_follow_group(member, group)

    %{
      owner: owner,
      owner_account: owner_account,
      member: member,
      member_account: member_account,
      group: group
    }
  end

  defp group_path(group), do: "/&#{group.character.username}"

  # the same for every preview viewer
  defp assert_minimal_header(session) do
    session
    |> assert_has(@header_name, text: "Preview header club")
    |> assert_has(@compact_hero)
    |> assert_has("#{@hero}[data-variant=visitor] [data-role=group-hero-actions]", text: "Join")
    |> assert_has("#group_access_gate", text: "You don't have access to this group's contents.")
    |> refute_has(@toggle)
    |> refute_has("[data-role=group-hero-banner]")
    |> refute_has("main", text: @summary)
    |> refute_has("[data-role=group-hero-facepile]")
    |> refute_has("[data-role=group-hero-members]")
    |> refute_has("[data-id=group_widget]")
  end

  test "a member gets the hero folded behind the toggle, with the group's name in the page header",
       %{member: member, member_account: account, group: group} do
    conn(user: member, account: account)
    |> visit(group_path(group))
    |> wait_async()
    |> assert_has(@header_name, text: "Preview header club")
    |> assert_has(@header_icon)
    |> assert_has(@compact_hero)
    |> assert_has(@toggle)
    |> assert_has("[data-role=group-hero-banner]")
    |> assert_has("#{@hero} [data-role=group-hero-members]", text: "2 members")
    |> refute_has("#group_access_gate")
  end

  test "a local non-member gets the minimal header: icon and name, Join and the gate", %{
    group: group
  } do
    account = fake_account!()
    visitor = fake_user!(account)
    refute Categories.member?(visitor, group), "control: not a member"

    conn(user: visitor, account: account)
    |> visit(group_path(group))
    |> wait_async()
    |> assert_has(@header_icon)
    |> assert_minimal_header()
  end

  test "a guest gets the same minimal header", %{group: group} do
    conn()
    |> get_conn_render(group_path(group))
    |> assert_has(@header_icon)
    |> assert_minimal_header()
  end

  test "a non-member instance admin gets the same header, and the members tab still lists everyone",
       %{group: group, member: member} do
    account = fake_account!()
    admin = fake_admin!(account)
    refute Categories.member?(admin, group), "control: not a member"

    conn(user: admin, account: account)
    |> visit(group_path(group))
    |> wait_async()
    |> assert_has(@header_icon)
    |> assert_minimal_header()

    conn(user: admin, account: account)
    |> visit(group_path(group) <> "/members")
    |> wait_async()
    |> assert_has("#directory-member-#{member.id}")
  end
end
