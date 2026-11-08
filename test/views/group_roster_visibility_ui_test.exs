defmodule Bonfire.UI.Groups.GroupRosterVisibilityUITest do
  @moduledoc """
  Who sees the list of a group's members follows who can join it (`Categories.roster_audience/1`). Where anyone can join, whoever can read the group sees the list. Where joining needs approval or an invite, members and moderators see it and everyone else sees how many there are, and a line says who can see it, in the words the group's visibility already has.
  """
  use Bonfire.UI.Groups.ConnCase, async: false
  @moduletag :ui

  alias Bonfire.Boundaries.Presets
  alias Bonfire.Classify.Categories
  alias Bonfire.Classify.Simulate

  setup do
    Process.put(:federating, false)
    Process.put([:bonfire, :default_pagination_limit], 10)

    moderator_account = fake_account!()
    moderator = fake_user!(moderator_account)
    member_account = fake_account!()
    member = fake_user!(member_account, %{name: "Quiet Member"})
    stranger_account = fake_account!()
    stranger = fake_user!(stranger_account)

    {:ok,
     moderator: moderator,
     moderator_account: moderator_account,
     member: member,
     member_account: member_account,
     stranger: stranger,
     stranger_account: stranger_account}
  end

  defp group_with(moderator, member, membership) do
    group =
      Simulate.fake_group!(moderator, %{
        membership: membership,
        visibility: "global",
        participation: "anyone",
        default_content_visibility: "public"
      })

    {:ok, _} = Categories.add_member(moderator, group, id(member), skip_boundary_check: true)
    assert Categories.member?(member, group), "control: a member"
    group
  end

  defp label_of(slug), do: Presets.dimension_meta(:visibility, slug)[:label]

  test "on a group joined by request, a stranger sees how many members there are and not who", %{
    moderator: moderator,
    member: member,
    stranger: stranger,
    stranger_account: stranger_account
  } do
    group = group_with(moderator, member, "on_request")

    conn(user: stranger, account: stranger_account)
    |> visit("/group/#{group.character.username}/members")
    |> wait_async()
    |> assert_has("#members-directory-count")
    |> refute_has("#directory-member-#{member.id}")
    |> refute_has("[data-role=remove_from_group]")
    |> assert_has("#members-roster-audience",
      text: "Who can see this list: #{label_of("members:private")}"
    )
  end

  test "on the same group, a member and the moderator see the names", %{
    moderator: moderator,
    moderator_account: moderator_account,
    member: member,
    member_account: member_account
  } do
    group = group_with(moderator, member, "on_request")

    for {user, account} <- [{member, member_account}, {moderator, moderator_account}] do
      conn(user: user, account: account)
      |> visit("/group/#{group.character.username}/members")
      |> wait_async()
      |> assert_has("#directory-member-#{member.id}")
    end
  end

  # an instance admin answers for who is in the groups hosted here, so they see the list, read-only
  test "on a group joined by request, an instance admin who is not a member sees the names", %{
    moderator: moderator,
    member: member
  } do
    group = group_with(moderator, member, "on_request")
    admin_account = fake_account!()
    admin = fake_admin!(admin_account)
    refute Categories.member?(admin, group), "control: not a member"
    refute Bonfire.Boundaries.can?(admin, :mediate, group), "control: cannot moderate the group"

    conn(user: admin, account: admin_account)
    |> visit("/group/#{group.character.username}/members")
    |> wait_async()
    |> assert_has("#members-directory-count", text: to_string(Categories.members_count(group)))
    |> assert_has("#directory-member-#{member.id}")
    |> assert_has("#directory-member-#{moderator.id}")
    |> refute_has("[data-role=remove_from_group]")
    |> refute_has("#members-roster-audience")
  end

  # seeing who is in the group is not seeing what is in it: the members tab gets through the gate for an instance admin, and every other tab stays gated
  test "on a group joined by request and only previewed by outsiders, an instance admin sees the names but still gets the gate on the group's contents",
       %{
         moderator: moderator,
         member: member,
         member_account: member_account,
         stranger: stranger,
         stranger_account: stranger_account
       } do
    group =
      Simulate.fake_group!(moderator, %{
        membership: "on_request",
        visibility: "nonfederated:preview",
        participation: "group_members",
        default_content_visibility: "public"
      })

    {:ok, _} = Categories.add_member(moderator, group, id(member), skip_boundary_check: true)
    admin_account = fake_account!()
    admin = fake_admin!(admin_account)
    refute Bonfire.Boundaries.can?(admin, :read, group), "control: cannot read the group"

    # control: a member gets past the gate on the feed and the topics
    member_conn = conn(user: member, account: member_account)

    for tab_path <- ["", "/topics"] do
      member_conn
      |> visit("/group/#{group.character.username}#{tab_path}")
      |> wait_async()
      |> refute_has("#group_access_gate")
    end

    # a non-member who is not an admin gets the gate on the members tab, as before
    conn(user: stranger, account: stranger_account)
    |> visit("/group/#{group.character.username}/members")
    |> wait_async()
    |> assert_has("#group_access_gate")
    |> refute_has("#directory-member-#{member.id}")

    conn = conn(user: admin, account: admin_account)

    conn
    |> visit("/group/#{group.character.username}/members")
    |> wait_async()
    |> refute_has("#group_access_gate")
    |> assert_has("#directory-member-#{member.id}")

    for tab_path <- ["", "/topics"] do
      conn
      |> visit("/group/#{group.character.username}#{tab_path}")
      |> wait_async()
      |> assert_has("#group_access_gate", text: "You don't have access to this group's contents.")
      |> refute_has("[data-id=feed]")
    end
  end

  test "on a group joined by request, an instance moderator who is not an admin sees only the moderators",
       %{moderator: moderator, member: member} do
    group = group_with(moderator, member, "on_request")
    instance_mod_account = fake_account!()
    {:ok, instance_mod} = Bonfire.Me.Users.make_moderator(fake_user!(instance_mod_account))
    refute Bonfire.Me.Accounts.is_admin?(instance_mod), "control: not an admin"

    conn(user: instance_mod, account: instance_mod_account)
    |> visit("/group/#{group.character.username}/members")
    |> wait_async()
    |> assert_has("#directory-member-#{moderator.id}")
    |> refute_has("#directory-member-#{member.id}")
    |> assert_has("#members-roster-audience",
      text: "Who can see this list: #{label_of("members:private")}"
    )
  end

  # a mirror's list is its origin's to show
  test "on a mirror of a group joined by request, an instance admin sees what a non-member sees",
       %{moderator: moderator, member: member} do
    group = group_with(moderator, member, "on_request")

    assert {:ok, _} =
             Bonfire.Federate.ActivityPub.Peered.save_canonical_uri(
               group,
               "https://elsewhere.local/c/roster_mirror"
             )

    admin_account = fake_account!()
    admin = fake_admin!(admin_account)

    conn(user: admin, account: admin_account)
    |> visit("/group/#{group.character.username}/members")
    |> wait_async()
    |> assert_has("#directory-member-#{moderator.id}")
    |> refute_has("#directory-member-#{member.id}")
    |> assert_has("#members-roster-audience",
      text: "Who can see this list: #{label_of("members:private")}"
    )
  end

  # followers are part of the roster as much as members are
  test "on a group joined by request, the followers are for members and moderators too", %{
    moderator: moderator,
    moderator_account: moderator_account,
    member: member,
    stranger: stranger,
    stranger_account: stranger_account
  } do
    group = group_with(moderator, member, "on_request")
    follower = fake_user!(fake_account!(), %{name: "Distant Follower"})
    {:ok, _} = Bonfire.Social.Graph.Follows.follow(follower, group, skip_boundary_check: true)

    conn(user: moderator, account: moderator_account)
    |> visit("/group/#{group.character.username}/followers")
    |> wait_async()
    |> assert_has("main", text: "Distant")

    conn(user: stranger, account: stranger_account)
    |> visit("/group/#{group.character.username}/followers")
    |> wait_async()
    |> refute_has("main", text: "Distant")
  end

  # the page offers no "Load more" to someone who may not see the list, and an event sent by hand gets nothing either
  test "on a group joined by request, a load more sent by hand returns no followers", %{
    moderator: moderator,
    member: member,
    stranger: stranger,
    stranger_account: stranger_account
  } do
    group = group_with(moderator, member, "on_request")
    follower = fake_user!(fake_account!(), %{name: "Distant Follower"})
    {:ok, _} = Bonfire.Social.Graph.Follows.follow(follower, group, skip_boundary_check: true)

    conn(user: stranger, account: stranger_account)
    |> visit("/group/#{group.character.username}/followers")
    |> wait_async()
    |> PhoenixTest.unwrap(fn view ->
      Phoenix.LiveViewTest.render_hook(view, "Bonfire.Social.Graph.Follows:load_more", %{
        "context" => "followers"
      })
    end)
    |> refute_has("main", text: "Distant")
  end

  test "on a group joined by request, a load more of members sent by hand returns none", %{
    moderator: moderator,
    member: member,
    stranger: stranger,
    stranger_account: stranger_account
  } do
    group = group_with(moderator, member, "on_request")

    conn(user: stranger, account: stranger_account)
    |> visit("/group/#{group.character.username}/members")
    |> wait_async()
    |> PhoenixTest.unwrap(fn view ->
      Phoenix.LiveViewTest.render_hook(view, "Bonfire.Classify:load_more", %{
        "context" => "members"
      })
    end)
    |> refute_has("main", text: "Quiet Member")
  end

  # the faces at the top of the group's page are the first few members, so they follow the same rule as the list
  test "on a group joined by request, a stranger sees no members' faces at the top of the page",
       %{
         moderator: moderator,
         member: member,
         member_account: member_account,
         stranger: stranger,
         stranger_account: stranger_account
       } do
    group = group_with(moderator, member, "on_request")

    conn(user: member, account: member_account)
    |> visit("/group/#{group.character.username}")
    |> wait_async()
    |> assert_has("[data-role=group-hero-facepile]")

    conn(user: stranger, account: stranger_account)
    |> visit("/group/#{group.character.username}")
    |> wait_async()
    |> refute_has("[data-role=group-hero-facepile]")
    |> assert_has("[data-role=group-hero-members]")
  end

  # found on prod: the followers page of a group listed its followers, but "Load more" answered "User not found", since the load-more handler looks for the profile's `user` and a group page has its `category`
  test "on a group anyone can join, the followers page loads more", %{
    moderator: moderator,
    member: member,
    stranger: stranger,
    stranger_account: stranger_account
  } do
    group = group_with(moderator, member, "open")

    trees = ~w(Alder Birch Cedar Dogwood Elm Fir Ginkgo Hazel Ironwood Juniper Larch Maple)

    for tree <- trees do
      follower = fake_user!(fake_account!(), %{name: "Tree #{tree}"})
      {:ok, _} = Bonfire.Social.Graph.Follows.follow(follower, group, skip_boundary_check: true)
    end

    session =
      conn(user: stranger, account: stranger_account)
      |> visit("/group/#{group.character.username}/followers")
      |> wait_async()
      |> assert_has("#load_more_followers")
      |> click_button("#load_more_followers", "")
      |> wait_async()
      |> refute_has("[role=alert]", text: "User not found")

    for tree <- trees, do: assert_has(session, "main", text: "Tree #{tree}")
  end

  test "on a group anyone can join, a stranger sees the names", %{
    moderator: moderator,
    member: member,
    stranger: stranger,
    stranger_account: stranger_account
  } do
    group = group_with(moderator, member, "open")

    conn(user: stranger, account: stranger_account)
    |> visit("/group/#{group.character.username}/members")
    |> wait_async()
    |> assert_has("#directory-member-#{member.id}")
    |> refute_has("#members-roster-audience", text: label_of("members:private"))
  end
end
