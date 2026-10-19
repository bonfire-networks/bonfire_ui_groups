defmodule Bonfire.UI.Groups.GroupBanUITest do
  @moduledoc """
  A group's moderators keeping someone out of the group, from where they meet them: a reported post on the group's moderation page, and the group's members list. Both show the person's ghost, silence and block buttons (`Bonfire.UI.Boundaries.BlockMenuButtonsLive` given the group as `scope`), and each of those, as well as acting for oneself, offers the same action "in the group" (silenced: no posting, replying or reacting there, still reading; ghosted: not seeing it either; blocked: both), and lifting it again. It is `Blocks.block/3` with `on_behalf_of: group`, so only someone who may moderate the group (`:mediate`) is offered it.
  """
  use Bonfire.UI.Groups.ConnCase, async: false
  @moduletag :ui

  alias Bonfire.Boundaries
  alias Bonfire.Boundaries.Blocks
  alias Bonfire.Classify.Categories
  alias Bonfire.Classify.Simulate

  setup do
    Process.put(:federating, false)
    # the moderation inbox holds more than the test page size of 2
    Process.put([:bonfire, :default_pagination_limit], 10)

    moderator_account = fake_account!()
    moderator = fake_user!(moderator_account)
    author = fake_user!(fake_account!(), %{name: "Troublesome Author"})
    member_account = fake_account!()
    member = fake_user!(member_account)
    reporter = fake_user!(fake_account!())

    group =
      Simulate.fake_group!(moderator, %{
        membership: "open",
        visibility: "global",
        participation: "anyone",
        default_content_visibility: "public"
      })

    {:ok, _} = Categories.join_and_follow_group(author, group)
    {:ok, _} = Categories.join_and_follow_group(member, group)
    post = Simulate.fake_post_in_group!(author, group, "<p>A post that got reported</p>")
    {:ok, _} = Bonfire.Social.Flags.flag(reporter, post, comment: "spam")

    # replying is checked through what publishing a reply checks (`Threads.find_reply_to/2`, raising when refused): the person blocked here is the post's author, and `Boundaries.can?/4` says yes to an object's creator before looking at any grant
    assert {:ok, _} = Bonfire.Social.Threads.find_reply_to(%{reply_to_id: post.id}, author),
           "control: the author may reply before any block"

    {:ok,
     moderator: moderator,
     moderator_account: moderator_account,
     author: author,
     member: member,
     member_account: member_account,
     group: group,
     post: post}
  end

  test "from a reported post, a moderator can silence its author in the group", %{
    moderator: moderator,
    moderator_account: moderator_account,
    author: author,
    group: group,
    post: post
  } do
    conn(user: moderator, account: moderator_account)
    |> visit("/group/#{group.character.username}/settings/moderation")
    |> wait_async()
    |> click_button("[data-role=open_modal]", "Silence Troublesome Author")
    |> open_browser()
    |> click_button("[data-role=block_from_group]", "Silence in the group")

    # silenced: can't reply in the group
    assert_raise Bonfire.Fail, fn ->
      Bonfire.Social.Threads.find_reply_to(%{reply_to_id: post.id}, author)
    end

    assert Boundaries.can?(author, :read, post), "but can still read it"

    refute Blocks.is_blocked?(author, :silence, current_user: moderator),
           "the group's block, not the moderator's"
  end

  # The box does two things: it removes the person from the group's followers (a ghost; a silence keeps the follow) and it sends the ban to other instances. A peer can only act on a ban as a silence (Lemmy, PieFed and Mbin read it so), and a ghost alone keeps someone from SEEING the group, which a peer holding a public copy can't enforce, so a ghost sends nothing: its box is only the follower removal, and says so
  test "the Ghost form in the group offers the box and says nothing is sent to other instances", %{
    moderator: moderator,
    moderator_account: moderator_account,
    group: group
  } do
    conn(user: moderator, account: moderator_account)
    |> visit("/group/#{group.character.username}/settings/moderation")
    |> wait_async()
    |> click_button("[data-role=open_modal]", "Ghost Troublesome Author")
    |> assert_has("[data-role=group_block] [data-role=also_unfollow_and_notify]")
    |> assert_has("[data-role=group_block]", text: "Nothing is sent to other instances")
    |> assert_has("[data-role=group_block]", text: "stops sending them its posts")
    |> refute_has("[data-role=group_block]", text: "Tell other instances too")
  end

  # A block includes a ghost, so its box also removes the person from the group's followers and says so. A silence keeps the follow, so its box must not
  for {type, ghosts?} <- [{"Silence", false}, {"Block", true}] do
    test "the #{type} form in the group offers to tell other instances, and #{if ghosts?, do: "says it removes them from the followers", else: "does not mention ghosting"}",
         %{moderator: moderator, moderator_account: moderator_account, group: group} do
      session =
        conn(user: moderator, account: moderator_account)
        |> visit("/group/#{group.character.username}/settings/moderation")
        |> wait_async()
        |> click_button("[data-role=open_modal]", "#{unquote(type)} Troublesome Author")
        |> assert_has("[data-role=group_block] [data-role=also_unfollow_and_notify]")
        |> assert_has("[data-role=group_block]", text: "Tell other instances too")
        |> refute_has("[data-role=group_block]", text: "Nothing is sent to other instances")

      if unquote(ghosts?) do
        assert_has(session, "[data-role=group_block]", text: "Ghosting also removes")
      else
        refute_has(session, "[data-role=group_block]", text: "Ghosting also removes")
        refute_has(session, "[data-role=group_block]", text: "a follow the ghost removed")
      end
    end
  end

  test "from the members list, a moderator can lift a block from the group", %{
    moderator: moderator,
    moderator_account: moderator_account,
    author: author,
    group: group,
    post: post
  } do
    assert {:ok, _} =
             Blocks.block(author, :silence, current_user: moderator, on_behalf_of: group)

    # control: the block took effect
    assert_raise Bonfire.Fail, fn ->
      Bonfire.Social.Threads.find_reply_to(%{reply_to_id: post.id}, author)
    end

    conn(user: moderator, account: moderator_account)
    |> visit("/group/#{group.character.username}/members")
    |> wait_async()
    |> within("#directory-member-#{author.id}", fn session ->
      click_button(session, "[data-role=open_modal]", "Silence Troublesome Author")
    end)
    |> click_button("[data-role=unblock_from_group]", "Unsilence in the group")

    assert {:ok, _} = Bonfire.Social.Threads.find_reply_to(%{reply_to_id: post.id}, author),
           "unblocked: can reply again"
  end

  test "a member who isn't a moderator isn't offered it on the members list", %{
    moderator: moderator,
    moderator_account: moderator_account,
    author: author,
    member_account: member_account,
    member: member,
    group: group
  } do
    # the control, so its absence below means the member's standing and not a list that never offers it
    conn(user: moderator, account: moderator_account)
    |> visit("/group/#{group.character.username}/members")
    |> wait_async()
    |> within("#directory-member-#{author.id}", fn session ->
      assert_has(session, "[data-role=open_modal]", text: "Silence Troublesome Author")
    end)

    conn(user: member, account: member_account)
    |> visit("/group/#{group.character.username}/members")
    |> wait_async()
    |> within("#directory-member-#{author.id}", fn session ->
      refute_has(session, "[data-role=open_modal]", text: "Silence Troublesome Author")
    end)
  end

  describe "removing someone from the group" do
    test "from the members list, a moderator can remove a member", %{
      moderator: moderator,
      moderator_account: moderator_account,
      author: author,
      group: group
    } do
      assert Categories.member?(author, group), "control: a member"
      assert Bonfire.Social.Graph.Follows.following?(author, group), "control: following"

      conn(user: moderator, account: moderator_account)
      |> visit("/group/#{group.character.username}/members")
      |> wait_async()
      |> within("#directory-member-#{author.id}", fn session ->
        click_button(session, "[data-role=remove_from_group]", "Remove from the group")
      end)
      |> refute_has("#directory-member-#{author.id}")

      refute Categories.member?(author, group)
      refute Bonfire.Social.Graph.Follows.following?(author, group)
    end

    test "from the members list in the group's settings, a moderator can remove a member", %{
      moderator: moderator,
      moderator_account: moderator_account,
      author: author,
      group: group
    } do
      assert Categories.member?(author, group), "control: a member"

      conn(user: moderator, account: moderator_account)
      |> visit("/&#{group.character.username}/settings")
      |> wait_async()
      |> within("#settings-person-#{author.id}", fn session ->
        click_button(session, "[data-role=remove_from_group]", "Remove from the group")
      end)
      |> refute_has("#settings-person-#{author.id}")

      refute Categories.member?(author, group)
      refute Bonfire.Social.Graph.Follows.following?(author, group)
    end

    test "is not offered to a member, nor on a moderator's own row", %{
      moderator: moderator,
      moderator_account: moderator_account,
      author: author,
      member: member,
      member_account: member_account,
      group: group
    } do
      conn(user: moderator, account: moderator_account)
      |> visit("/group/#{group.character.username}/members")
      |> wait_async()
      |> within("#directory-member-#{author.id}", fn session ->
        assert_has(session, "[data-role=remove_from_group]")
      end)
      |> within("#directory-member-#{moderator.id}", fn session ->
        refute_has(session, "[data-role=remove_from_group]")
      end)

      conn(user: member, account: member_account)
      |> visit("/group/#{group.character.username}/members")
      |> wait_async()
      |> within("#directory-member-#{author.id}", fn session ->
        refute_has(session, "[data-role=remove_from_group]")
      end)
    end
  end
end
