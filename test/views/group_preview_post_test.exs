defmodule Bonfire.UI.Groups.GroupPreviewPostTest do
  @moduledoc """
  A group whose posts default to a preview (`local:preview`: "Post appears in local feeds but full content is members-only"): anyone local may find such a post, its members may read it. So a non-member sees it listed in the group's feed but not its content, and a member sees it whole.
  """
  use Bonfire.UI.Groups.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  alias Bonfire.Boundaries
  alias Bonfire.Classify.Simulate

  @body "only members may read this far"

  setup do
    Process.put(:federating, false)
    Process.put([:bonfire, :feed_live_update_many_preload_mode], :inline)

    creator = fake_user!(fake_account!())

    group =
      Simulate.fake_group!(creator, %{
        membership: "open",
        visibility: "global",
        participation: "anyone",
        default_content_visibility: "local:preview"
      })

    author = fake_user!(fake_account!())

    {:ok, _} =
      Bonfire.Classify.Categories.add_member(creator, group, id(author),
        skip_boundary_check: true
      )

    post = Simulate.fake_post_in_group!(author, group, "<p>#{@body}</p>")

    {:ok, creator: creator, group: group, author: author, post: post}
  end

  defp group_feed(user, account, group) do
    conn(user: user, account: account)
    |> visit("/group/#{group.character.username}")
    |> wait_async()
  end

  test "a non-member finds the post in the group's feed, but not its content", %{
    group: group,
    post: post
  } do
    account = fake_account!()
    outsider = fake_user!(account)

    assert Boundaries.can?(outsider, :see, post), "control: they may find it"
    refute Boundaries.can?(outsider, :read, post), "control: but not read it"

    group_feed(outsider, account, group)
    |> assert_has("[data-object_id='#{id(post)}']")
    |> refute_has("[data-object_id='#{id(post)}']", text: @body)
    # in place of its body, why it isn't shown, naming the group that keeps it to its members
    |> assert_has("[data-object_id='#{id(post)}'] [data-role=restricted_object]")
    |> assert_has("[data-object_id='#{id(post)}'] [data-role=restricted_content_notice]",
      text: "Only members of #{e(group, :profile, :name, nil)} can read this"
    )
  end

  describe "opening it, for a non-member" do
    setup do
      previous =
        Bonfire.Common.Config.get(
          [Bonfire.UI.Social.RestrictedContentLive],
          nil,
          :bonfire_ui_social
        )

      on_exit(fn ->
        Bonfire.Common.Config.put(
          [Bonfire.UI.Social.RestrictedContentLive],
          previous,
          :bonfire_ui_social
        )
      end)

      account = fake_account!()
      {:ok, outsider: fake_user!(account), account: account}
    end

    test "shows the instance's restricted screen, when it has one", %{
      outsider: outsider,
      account: account,
      post: post
    } do
      Bonfire.Common.Config.put(
        [Bonfire.UI.Social.RestrictedContentLive, :modularity],
        true,
        :bonfire_ui_social
      )

      conn(user: outsider, account: account)
      |> visit("/post/#{id(post)}")
      |> wait_async()
      |> assert_has("[data-role=restricted_content]")
      |> assert_has("[data-role=restricted_content_notice]", text: "You can't read this")
      |> refute_has("body", text: @body)
    end

    test "says they can't view it, when it hasn't", %{
      outsider: outsider,
      account: account,
      post: post
    } do
      conn(user: outsider, account: account)
      |> visit("/post/#{id(post)}")
      |> wait_async()
      |> assert_has("[role=alert]", text: "Sorry, you can't view this")
      |> refute_has("body", text: @body)
    end
  end

  test "a member reads it", %{creator: creator, group: group, post: post} do
    account = fake_account!()
    member = fake_user!(account)

    {:ok, _} =
      Bonfire.Classify.Categories.add_member(creator, group, id(member),
        skip_boundary_check: true
      )

    assert Boundaries.can?(member, :read, post),
           "members may read what the group shows them a preview of"

    group_feed(member, account, group)
    |> assert_has("[data-object_id='#{id(post)}']", text: @body)
  end
end
