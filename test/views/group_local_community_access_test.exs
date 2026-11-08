defmodule Bonfire.UI.Groups.GroupLocalCommunityAccessTest do
  @moduledoc "Who reads a `local_community`-shaped group's posts: joins and posting open to local users, the group itself only previewed (`nonfederated:preview`), and posts defaulting to local users."
  use Bonfire.UI.Groups.ConnCase, async: false
  @moduletag :ui

  alias Bonfire.Classify.Categories

  setup do
    Process.put([:bonfire, :feed_live_update_many_preload_mode], :inline)
    Process.put(:federating, false)

    owner = fake_user!(fake_account!())

    # the settings UI labels: Join "Users of this instance", See "Discoverable group preview", Post "Users of this instance", New posts "Users of this instance"
    group =
      Bonfire.Classify.Simulate.fake_group!(owner, %{
        name: "Testgroep Ypsilon",
        membership: "local:members",
        visibility: "nonfederated:preview",
        participation: "local:contributors",
        default_content_visibility: "local"
      })

    author_account = fake_account!()
    author = fake_user!(author_account)
    assert {:ok, _} = Categories.join_and_follow_group(author, group)
    assert Categories.member?(author, group)

    post =
      Bonfire.Classify.Simulate.fake_post_in_group!(author, group, "<p>Ypsilon discussion</p>")

    %{owner: owner, group: group, author: author, author_account: author_account, post: post}
  end

  test "a local member who joined sees the group's posts", context do
    account = fake_account!()
    member = fake_user!(account)
    assert {:ok, _} = Categories.join_and_follow_group(member, context.group)
    assert Categories.member?(member, context.group)

    assert {:ok, _} = Bonfire.Posts.read(context.post.id, current_user: member)

    conn(user: member, account: account)
    |> visit("/&#{context.group.character.username}")
    |> wait_async()
    |> refute_has("#group_access_gate")
    |> assert_has("[data-id=feed]", text: "Ypsilon discussion")
  end

  test "the member who posted sees the group's posts", context do
    conn(user: context.author, account: context.author_account)
    |> visit("/&#{context.group.character.username}")
    |> wait_async()
    |> refute_has("#group_access_gate")
    |> assert_has("[data-id=feed]", text: "Ypsilon discussion")
  end

  test "a local non-member gets the gate, though the post itself is readable to them", context do
    account = fake_account!()
    visitor = fake_user!(account)
    refute Categories.member?(visitor, context.group)

    # the post's own boundary ("New posts: Users of this instance") lets any local user read it
    assert {:ok, _} = Bonfire.Posts.read(context.post.id, current_user: visitor)
    # but the group grants local users `:see`, not `:read`
    assert Bonfire.Boundaries.can?(visitor, :see, context.group)
    refute Bonfire.Boundaries.can?(visitor, :read, context.group)

    conn(user: visitor, account: account)
    |> visit("/&#{context.group.character.username}")
    |> wait_async()
    |> assert_has("#group_access_gate", text: "You don't have access to this group's contents.")
    |> refute_has("[data-id=feed]")
  end

  test "an instance admin who is not a member", context do
    account = fake_account!()
    admin = Bonfire.UI.Common.Testing.Helpers.fake_admin!(account)
    refute Categories.member?(admin, context.group)

    assert {:ok, _} = Bonfire.Posts.read(context.post.id, current_user: admin)
    refute Bonfire.Boundaries.can?(admin, :read, context.group)

    conn(user: admin, account: account)
    |> visit("/&#{context.group.character.username}")
    |> wait_async()
    |> assert_has("#group_access_gate", text: "You don't have access to this group's contents.")
    |> refute_has("[data-id=feed]")
  end
end
