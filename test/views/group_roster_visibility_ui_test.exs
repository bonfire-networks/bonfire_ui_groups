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
