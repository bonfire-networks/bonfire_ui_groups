defmodule Bonfire.UI.Groups.GroupPostRemovalTest do
  @moduledoc """
  Removing a post from a group (the flagged-items menu's "Remove this post from the group") takes the group's boost of it away, so it leaves the group's feed while the post itself survives. Only someone who moderates the group may do it.

  The menu only shows the button to moderators, but the event it fires (`Bonfire.Social.Flags:unpublish`) can be sent by anyone with a LiveView open, so the check has to be in the handler. These tests send the event directly, as a crafted request would.
  """
  use Bonfire.UI.Groups.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  alias Bonfire.Classify.Simulate

  setup do
    Process.put(:federating, false)

    creator = fake_user!(fake_account!())
    account = fake_account!()
    moderator = fake_user!(account)
    author_account = fake_account!()
    author = fake_user!(author_account)
    group = Simulate.fake_group!(creator, %{membership: "open"})
    # a promoted moderator, not the creator, who could pass on being the group's creator alone
    {:ok, _} = Bonfire.Classify.Categories.add_moderator(creator, group, id(moderator))
    assert {:ok, _} = Bonfire.Classify.Categories.join_group(author, group)
    post = Simulate.fake_post_in_group!(author, group, "<p>Removable</p>")

    assert Bonfire.Social.Boosts.boosted?(group, post),
           "control: the post is in the group's feed to begin with"

    {:ok,
     account: account,
     moderator: moderator,
     author_account: author_account,
     author: author,
     group: group,
     post: post}
  end

  defp remove_from_group(user, account, group, post) do
    {:ok, view, _html} =
      live(conn(user: user, account: account), "/group/#{group.character.username}")

    render_hook(view, "Bonfire.Social.Flags:unpublish", %{
      "id" => id(post),
      "context" => id(group)
    })
  end

  test "a moderator of the group can remove a post from it", %{
    account: account,
    moderator: moderator,
    group: group,
    post: post
  } do
    remove_from_group(moderator, account, group, post)

    refute Bonfire.Social.Boosts.boosted?(group, post)
  end

  test "someone who doesn't moderate the group can't", %{group: group, post: post} do
    stranger_account = fake_account!()
    stranger = fake_user!(stranger_account)

    remove_from_group(stranger, stranger_account, group, post)

    assert Bonfire.Social.Boosts.boosted?(group, post),
           "a non-moderator took a post out of someone else's group"
  end

  # the post's own menu, beside delete, for whoever may remove it: the flagged-items menu is only reached once someone reports the post, and an author never reaches it
  describe "the post's menu" do
    # the menu is the "Advanced" modal, whose content only mounts once it opens, so each test opens it as a user would. On the post's own page, where it's rendered up front (in a feed it isn't), as `change_object_boundary_test.exs` does
    defp open_post_menu(user, account, post) do
      conn(user: user, account: account)
      |> visit("/post/#{id(post)}")
      |> wait_async()
      |> assert_has("article", text: "Removable")
      |> click_button("Advanced")
    end

    test "offers the author \"Remove from group\", which takes the post out", %{
      author_account: author_account,
      author: author,
      group: group,
      post: post
    } do
      open_post_menu(author, author_account, post)
      |> click_button("[data-role=remove_from_group_confirm]", "Remove from group")

      refute Bonfire.Social.Boosts.boosted?(group, post)
    end

    test "offers a moderator \"Remove from group\" on someone else's post, which takes it out", %{
      account: account,
      moderator: moderator,
      group: group,
      post: post
    } do
      open_post_menu(moderator, account, post)
      |> click_button("[data-role=remove_from_group_confirm]", "Remove from group")

      refute Bonfire.Social.Boosts.boosted?(group, post)
    end

    test "doesn't offer it to someone who may not remove the post", %{post: post} do
      stranger_account = fake_account!()
      stranger = fake_user!(stranger_account)

      open_post_menu(stranger, stranger_account, post)
      # the control: the menu did open, so the button's absence is the permission, not an unmounted modal
      |> assert_has("h3", text: "Boundary")
      |> refute_has("[data-role=remove_from_group_confirm]")
    end
  end
end
