defmodule Bonfire.UI.Groups.SidebarGroupTest do
  use Bonfire.UI.Groups.ConnCase, async: false

  alias Bonfire.UI.Groups.SidebarGroupLive

  setup do
    Process.put(:federating, false)
    user = fake_user!()
    group = Bonfire.Classify.Simulate.fake_group!(user, %{visibility: "global"})
    topic = Bonfire.Classify.Simulate.fake_category!(user, group, %{name: Faker.Lorem.words(3) |> Enum.join(" "), username: "topic#{System.unique_integer([:positive])}", type: :topic})
    %{user: user, group: group, topic: topic}
  end

  test "topic navigation opens its group and preserves the entry page", %{group: group, topic: topic} do
    html = render_component(&SidebarGroupLive.render/1,
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
    assert [_] = Floki.find(document, "a[aria-current='page'][href*='group_from=%2Ffeed%3Fsort%3Dlatest']")
    assert Floki.attribute(document, "a[aria-current='page']", "title") == [topic.profile.name]
  end

  test "other groups start collapsed and empty groups have no disclosure", %{group: group, topic: topic} do
    render = fn children ->
      render_component(&SidebarGroupLive.render/1,
        category: group, children: children, parent_id: "sidebar", current_path: "/feed"
      ) |> Floki.parse_document!()
    end

    assert [_] = Floki.find(render.([{topic, []}]), "details:not([open])")
    assert [] == Floki.find(render.([]), "details")
  end

  test "pinned groups include only visible direct topics", %{user: user, group: group, topic: topic} do
    other = fake_user!()
    {:ok, _} = Bonfire.Social.Pins.pin(other, group, nil, to_feeds: [])
    descendant = Bonfire.Classify.Simulate.fake_category!(user, topic, %{name: Faker.Lorem.word(), type: :topic})
    tree = Bonfire.Classify.my_pinned_tree(other)
    {_, children} = Enum.find(tree, fn {pinned, _} -> pinned.id == group.id end)
    assert Enum.any?(children, fn {child, _} -> child.id == topic.id end)
    refute Enum.any?(children, fn {child, _} -> child.id == descendant.id end)

    assert {:ok, _} = Bonfire.Boundaries.Blocks.block(topic, :silence, current_user: other)
    {_, children} = Enum.find(Bonfire.Classify.my_pinned_tree(other), fn {pinned, _} -> pinned.id == group.id end)
    refute Enum.any?(children, fn {child, _} -> child.id == topic.id end)
  end
end
