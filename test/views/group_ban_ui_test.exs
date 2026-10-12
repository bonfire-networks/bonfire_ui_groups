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
end
