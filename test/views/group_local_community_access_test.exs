defmodule Bonfire.UI.Groups.GroupLocalCommunityAccessTest do
  @moduledoc "Who reads a group's posts. The main setup spells out a group whose joins and posting are open to local users, that is only previewed (`nonfederated:preview`) and whose posts default to local users (the shape `local_community` had before it became readable); the `local_community` preset itself is tested in its own describe."
  use Bonfire.UI.Groups.ConnCase, async: false
  @moduletag :ui

  alias Bonfire.Classify.Categories

  setup do
    Process.put([:bonfire, :feed_live_update_many_preload_mode], :inline)
    Process.put(:federating, false)

    owner_account = fake_account!()
    owner = fake_user!(owner_account)

    # explicit dimensions rather than the preset, so this stays a preview-only group whatever the preset says. The settings UI labels: Join "Users of this instance", See "Anyone can preview (but doesn't federate)", Post "Users of this instance", New posts "Users of this instance"
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

    %{
      owner: owner,
      owner_account: owner_account,
      group: group,
      author: author,
      author_account: author_account,
      post: post
    }
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

  # the creator edits the group through the real settings form (open "Custom group boundaries", pick an option, save), and a member who joined before the edit must still read the group
  defp edit_group_boundaries_as_owner(context, dim, pick) do
    conn(user: context.owner, account: context.owner_account)
    |> visit("/&#{context.group.character.username}/settings/boundaries")
    |> wait_async()
    |> unwrap(fn view ->
      import Phoenix.LiveViewTest

      # a group matching no preset opens the settings with Advanced already open
      if has_element?(view, "button[phx-click=toggle_advanced][aria-expanded=false]"),
        do: view |> element("button[phx-click=toggle_advanced]") |> render_click()

      view |> element(pick.(dim)) |> render_click()
      view |> element("#group_settings_boundaries_form") |> render_submit()
    end)
  end

  defp assert_member_reads_group(context, member, account) do
    conn(user: member, account: account)
    |> visit("/&#{context.group.character.username}")
    |> wait_async()
    |> refute_has("#group_access_gate")
    |> assert_has("[data-id=feed]", text: "Ypsilon discussion")
  end

  test "a member still reads the group after its creator changes `See content` to Public",
       context do
    account = fake_account!()
    member = fake_user!(account)
    assert {:ok, _} = Categories.join_and_follow_group(member, context.group)
    assert Categories.member?(member, context.group)

    # positive first: the member reads the group before the edit
    assert_member_reads_group(context, member, account)

    edit_group_boundaries_as_owner(context, :default_content_visibility, fn dim ->
      "button[phx-click='Bonfire.Classify:set_boundary_scope'][phx-value-dim=#{dim}][phx-value-scope=nonfederated]"
    end)

    assert Bonfire.Boundaries.can?(member, :read, context.group)
    assert_member_reads_group(context, member, account)
  end

  test "a member still reads the group after its creator changes who can post", context do
    account = fake_account!()
    member = fake_user!(account)
    assert {:ok, _} = Categories.join_and_follow_group(member, context.group)
    assert Categories.member?(member, context.group)

    assert_member_reads_group(context, member, account)

    edit_group_boundaries_as_owner(context, :participation, fn dim ->
      "button[phx-click='Bonfire.Classify:set_boundary_dimensions'][phx-value-dim=#{dim}][phx-value-slug=group_members]"
    end)

    assert Bonfire.Boundaries.Presets.group_dimension_slugs(%{id: context.group.id}).participation ==
             "group_members"

    assert Bonfire.Boundaries.can?(member, :read, context.group)
    assert_member_reads_group(context, member, account)
  end

  # a group made from the `local_community` preset itself (not from its dimensions spelled out, as the setup's is), so the preset's own `visibility` is what's tested: users of this instance and guests read it
  describe "a group created from the local_community preset" do
    setup context do
      # the dimensions the preset declares, as the create-group form sends them
      preset_dims =
        Bonfire.Common.Config.get([:group_presets, "local_community"], %{}, :bonfire_classify)
        |> Map.take([:membership, :visibility, :participation, :default_content_visibility])

      preset_group =
        Bonfire.Classify.Simulate.fake_group!(
          context.owner,
          Map.merge(%{name: "Preset Ypsilon", preset_slug: "local_community"}, preset_dims)
        )

      post =
        Bonfire.Classify.Simulate.fake_post_in_group!(
          context.owner,
          preset_group,
          "<p>Preset discussion</p>"
        )

      %{preset_group: preset_group, preset_post: post}
    end

    test "a local non-member sees the feed, not the gate", context do
      account = fake_account!()
      visitor = fake_user!(account)
      refute Categories.member?(visitor, context.preset_group)
      assert Bonfire.Boundaries.can?(visitor, :read, context.preset_group)

      conn(user: visitor, account: account)
      |> visit("/&#{context.preset_group.character.username}")
      |> wait_async()
      |> refute_has("#group_access_gate")
      |> assert_has("[data-id=feed]", text: "Preset discussion")
    end

    test "a guest gets the group's page, not the gate", context do
      # a guest has no LiveView socket, so the page they get is the static render
      conn()
      |> get_conn_render("/&#{context.preset_group.character.username}")
      |> refute_has("#group_access_gate")
      |> refute_has("[data-role=category_preview]")
    end
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
