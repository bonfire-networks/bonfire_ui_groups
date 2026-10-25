defmodule Bonfire.UI.Groups.SidebarGroupTest do
  use Bonfire.UI.Groups.ConnCase, async: false

  alias Bonfire.UI.Groups.SidebarGroupLive

  setup do
    Process.put(:federating, false)
    user = fake_user!()
    group = Bonfire.Classify.Simulate.fake_group!(user, %{visibility: "global"})

    topic =
      Bonfire.Classify.Simulate.fake_category!(user, group, %{
        name: Faker.Lorem.words(3) |> Enum.join(" "),
        username: "topic#{System.unique_integer([:positive])}",
        type: :topic
      })

    %{user: user, group: group, topic: topic}
  end

  test "topic navigation opens its group and preserves the entry page", %{
    group: group,
    topic: topic
  } do
    html =
      render_component(&SidebarGroupLive.render/1,
        category: group,
        children: [{topic, []}],
        parent_id: "sidebar",
        current_path: Bonfire.Common.URIs.path(group) <> "/topic/" <> topic.character.username,
        group_return_to: "/feed?sort=latest"
      )

    document = Floki.parse_document!(html)

    assert [_] = Floki.find(document, "details[open]")
    assert [_] = Floki.find(document, "summary[aria-label]")
    assert [] == Floki.find(document, "summary a")

    assert [_] =
             Floki.find(
               document,
               "a[aria-current='page'][href*='group_from=%2Ffeed%3Fsort%3Dlatest']"
             )

    assert Floki.attribute(document, "a[aria-current='page']", "title") == [topic.profile.name]
  end

  test "other groups start collapsed and empty groups have no disclosure", %{
    group: group,
    topic: topic
  } do
    render = fn children ->
      render_component(&SidebarGroupLive.render/1,
        category: group,
        children: children,
        parent_id: "sidebar",
        current_path: "/feed"
      )
      |> Floki.parse_document!()
    end

    assert [_] = Floki.find(render.([{topic, []}]), "details:not([open])")
    assert [] == Floki.find(render.([]), "details")
  end

  test "row menu offers removing the group from the sidebar", %{group: group} do
    document =
      render_component(&SidebarGroupLive.render/1,
        category: group,
        parent_id: "sidebar",
        current_path: "/feed"
      )
      |> Floki.parse_document!()

    assert [_] = Floki.find(document, "#sidebar-group-#{group.id}-menu_trigger")

    unpin = Floki.find(document, "[data-role=sidebar_group_unpin]")
    assert Floki.attribute(unpin, "phx-click") == ["Bonfire.Social.Pins:pin"]
    assert Floki.attribute(unpin, "phx-value-direction") == ["down"]
    assert Floki.attribute(unpin, "phx-value-id") == [group.id]
    assert Floki.attribute(unpin, "phx-value-scope") == ["sidebar"]
  end

  test "row menu offers copying the group link, and joining to a non-member", %{group: group} do
    document =
      render_component(&SidebarGroupLive.render/1,
        category: group,
        parent_id: "sidebar",
        current_path: "/feed",
        join_mode: "free"
      )
      |> Floki.parse_document!()

    copy = Floki.find(document, "[data-role=sidebar_group_copy_link]")
    assert Floki.attribute(copy, "phx-hook") == ["Copy"]
    assert [href] = Floki.attribute(copy, "href")
    assert String.starts_with?(href, "http")
    assert String.ends_with?(href, Bonfire.Common.URIs.path(group))

    join = Floki.find(document, "[data-role=sidebar_group_join]")
    assert Floki.attribute(join, "phx-click") == ["Bonfire.UI.Groups:join_group"]
    assert Floki.attribute(join, "phx-value-id") == [group.id]
    assert Floki.text(join) =~ "Join group"
    assert [] == Floki.find(document, "[data-role=sidebar_group_leave]")
  end

  test "the Join item follows the group's join mode and a pending request", %{group: group} do
    render = fn assigns ->
      render_component(
        &SidebarGroupLive.render/1,
        [category: group, parent_id: "sidebar", current_path: "/feed"] ++ assigns
      )
      |> Floki.parse_document!()
    end

    assert render.(join_mode: "request")
           |> Floki.find("[data-role=sidebar_group_join]")
           |> Floki.text() =~ "Request to join"

    invite = render.(join_mode: "invite")
    assert [] == Floki.find(invite, "[data-role=sidebar_group_join]")
    assert [] == Floki.find(invite, "[data-role=sidebar_group_leave]")

    pending = render.(join_mode: "request", my_membership: :requested)
    assert [_] = Floki.find(pending, "[data-role=sidebar_group_pending]")
    assert [] == Floki.find(pending, "[data-role=sidebar_group_join]")
  end

  test "members are offered leaving, which opens a confirmation rather than leaving", %{
    group: group
  } do
    document =
      render_component(&SidebarGroupLive.render/1,
        category: group,
        parent_id: "sidebar",
        current_path: "/feed",
        my_membership: true,
        join_mode: "invite"
      )
      |> Floki.parse_document!()

    leave = Floki.find(document, "[data-role=sidebar_group_leave]")
    assert Floki.attribute(leave, "phx-click") == ["Bonfire.UI.Groups:open_leave_confirm"]
    assert Floki.attribute(leave, "phx-value-id") == [group.id]
    assert Floki.attribute(leave, "aria-haspopup") == ["dialog"]
    assert Floki.attribute(leave, "phx-value-join-mode") == ["invite"]
    assert [] == Floki.find(document, "[data-role=sidebar_group_join]")
  end

  test "members get a bell in the row menu, loaded when the menu opens", %{group: group} do
    document =
      render_component(&SidebarGroupLive.render/1,
        category: group,
        parent_id: "sidebar",
        current_path: "/feed",
        my_membership: true
      )
      |> Floki.parse_document!()

    bell_id = "sidebar-group-#{group.id}-bell"
    assert [_] = Floki.find(document, "##{bell_id}[data-role=bell_menu_item]")

    assert [load] =
             Floki.attribute(document, "#sidebar-group-#{group.id}-menu_trigger", "phx-click")

    assert load =~ "##{bell_id}"
    # asked once: the trigger then drops its own phx-click
    assert load =~ ~s("remove_attr")
    assert load =~ "#sidebar-group-#{group.id}-menu_trigger"
    assert [] == Floki.find(document, "#sidebar-group-#{group.id}-follow")
  end

  test "non-members get no bell and the menu loads nothing on open", %{group: group} do
    document =
      render_component(&SidebarGroupLive.render/1,
        category: group,
        parent_id: "sidebar",
        current_path: "/feed",
        join_mode: "free"
      )
      |> Floki.parse_document!()

    assert [] == Floki.find(document, "[data-role=bell_menu_item]")
    assert [] == Floki.attribute(document, "#sidebar-group-#{group.id}-menu_trigger", "phx-click")
  end

  test "admin-pinned groups say so instead of offering a no-op unpin", %{group: group} do
    document =
      render_component(&SidebarGroupLive.render/1,
        category: group,
        parent_id: "sidebar",
        current_path: "/feed",
        instance_pinned: true
      )
      |> Floki.parse_document!()

    assert [] == Floki.find(document, "[data-role=sidebar_group_unpin]")
    assert [_] = Floki.find(document, "[data-role=sidebar_group_admin_pinned]")
  end

  test "pinned groups include only visible direct topics", %{
    user: user,
    group: group,
    topic: topic
  } do
    other = fake_user!()
    {:ok, _} = Bonfire.Social.Pins.pin(other, group, nil, to_feeds: [])

    descendant =
      Bonfire.Classify.Simulate.fake_category!(user, topic, %{
        name: Bonfire.Common.Simulation.word(),
        type: :topic
      })

    tree = Bonfire.Classify.my_pinned_tree(other)
    {_, children} = Enum.find(tree, fn {pinned, _} -> pinned.id == group.id end)
    assert Enum.any?(children, fn {child, _} -> child.id == topic.id end)
    refute Enum.any?(children, fn {child, _} -> child.id == descendant.id end)

    assert {:ok, _} = Bonfire.Boundaries.Blocks.block(topic, :silence, current_user: other)

    {_, children} =
      Enum.find(Bonfire.Classify.my_pinned_tree(other), fn {pinned, _} ->
        pinned.id == group.id
      end)

    refute Enum.any?(children, fn {child, _} -> child.id == topic.id end)
  end
end
