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
    # on the post's own page, where the main object is outside any stream, so the menu's rows reach the test DOM once loaded
    defp open_post_menu(user, account, post) do
      conn(user: user, account: account)
      |> visit("/post/#{id(post)}")
      |> wait_async()
      |> assert_has("article", text: "Removable")
      |> open_more_menu()
    end

    defp confirm_removal(session) do
      session
      |> click_button("[data-role=remove_from_group] [data-role=open_modal]", "Remove from group")
      |> click_button("[data-role=remove_from_group_confirm]", "Remove from group")
    end

    test "offers the author \"Remove from group\", which takes the post out", %{
      author_account: author_account,
      author: author,
      group: group,
      post: post
    } do
      open_post_menu(author, author_account, post)
      |> confirm_removal()

      refute Bonfire.Social.Boosts.boosted?(group, post)
    end

    test "offers a moderator \"Remove from group\" on someone else's post, which takes it out", %{
      account: account,
      moderator: moderator,
      group: group,
      post: post
    } do
      open_post_menu(moderator, account, post)
      |> confirm_removal()

      refute Bonfire.Social.Boosts.boosted?(group, post)
    end

    # instance-wide rights (lock, pin to the instance) are in the same menu: they must not take the group's row away
    test "offers it to a group moderator who is also an instance admin", %{
      account: account,
      moderator: moderator,
      group: group,
      post: post
    } do
      {:ok, admin} = Bonfire.Me.Users.make_admin(moderator)

      open_post_menu(admin, account, post)
      |> assert_has("[data-role=remove_from_group]")
      |> confirm_removal()

      refute Bonfire.Social.Boosts.boosted?(group, post)
    end

    # the same menu opened from a feed card, where the group the post sits in comes with the activity
    test "offers a moderator \"Remove from group\" on the post's card in a feed", %{
      account: account,
      moderator: moderator,
      post: post
    } do
      conn(user: moderator, account: account)
      |> visit("/feed/local")
      |> wait_async()
      |> assert_has("article", text: "Removable")
      |> open_more_menu()
      # the control: the menu's permission rows did load, so a missing row is the permission
      |> assert_has("[data-id=boundary_details]")
      |> assert_has("[data-role=remove_from_group]")
    end

    test "doesn't offer it to someone who may not remove the post", %{post: post} do
      stranger_account = fake_account!()
      stranger = fake_user!(stranger_account)

      open_post_menu(stranger, stranger_account, post)
      # the control: the menu's permission rows did load, so the row's absence is the permission
      |> assert_has("[data-id=boundary_details]")
      |> refute_has("[data-role=remove_from_group]")
    end

    # not per post when a page renders (an N+1 on group feeds); the post's own page renders its menu as a feed row does
    test "isn't worked out when the post renders", %{
      account: account,
      moderator: moderator,
      post: post
    } do
      test_pid = self()
      stub_removal_check(test_pid)

      conn(user: moderator, account: account)
      |> visit("/post/#{id(post)}")
      |> wait_async()
      |> assert_has("[data-id=more_menu]")

      refute_receive :removal_checked
    end

    # the control for the test above: the moderator is still offered it, from the post's loaded boundary (its moderators may `:mediate` what is published in the group), so the per-group check never runs at all
    test "is decided from the post's loaded boundary, and offered to its moderator", %{
      account: account,
      moderator: moderator,
      post: post
    } do
      test_pid = self()
      stub_removal_check(test_pid)

      open_post_menu(moderator, account, post)
      |> assert_has("[data-role=remove_from_group]")

      refute_receive :removal_checked
    end

    # `mode: :shared` because the check runs in the LiveView process, not the test's
    defp stub_removal_check(test_pid) do
      Repatch.patch(
        Bonfire.Classify.Categories,
        :can_remove_post_from_group?,
        [mode: :shared],
        fn _user, _group, _post ->
          send(test_pid, :removal_checked)
          false
        end
      )
    end
  end
end
