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

  test "topic navigation opens its group", %{
    group: group,
    topic: topic
  } do
    topic_path = Bonfire.Classify.Web.GroupNavigation.topic_path(group, topic)

    html =
      render_component(&SidebarGroupLive.render/1,
        category: group,
        children: [{topic, []}],
        parent_id: "sidebar",
        current_path: topic_path
      )

    document = Floki.parse_document!(html)

    assert [_] = Floki.find(document, "details[open]")
    assert [_] = Floki.find(document, "summary[aria-label]")
    assert [] == Floki.find(document, "summary a")

    # the current row is the topic's, pointing at its plain path
    assert [_] = Floki.find(document, "a[aria-current='page'][href='#{topic_path}']")
    assert Floki.attribute(document, "a[aria-current='page']", "title") == [topic.profile.name]
  end

  # the rows sit in `PersistentLive`, a sticky view: a patch link is sent by the client to the main view, which patches when it serves the route and otherwise answers with a navigate, so the link needs no entry page in its href
  test "the group row and the topic row are patch links with the plain path", %{
    group: group,
    topic: topic
  } do
    group_path = Bonfire.Common.URIs.path(group)
    topic_path = Bonfire.Classify.Web.GroupNavigation.topic_path(group, topic)

    document =
      render_component(&SidebarGroupLive.render/1,
        category: group,
        children: [{topic, []}],
        parent_id: "sidebar",
        current_path: "/feed"
      )
      |> Floki.parse_document!()

    # positive first: both rows are there and go to the right paths
    assert [group_row] = Floki.find(document, "#sidebar-group-#{group.id}-link")
    assert Floki.attribute(group_row, "href") == [group_path]

    assert [topic_row] =
             Floki.find(document, "#sidebar-group-#{group.id}-topic-#{topic.id}")

    assert Floki.attribute(topic_row, "href") == [topic_path]

    for row <- [group_row, topic_row] do
      assert Floki.attribute(row, "data-phx-link") == ["patch"]
      refute hd(Floki.attribute(row, "href")) =~ "group_from"
    end
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

  test "a group mirrored from elsewhere, as the sidebar loads it, copies its id there", %{
    user: user
  } do
    mirrored = Bonfire.Classify.Simulate.fake_group!(user, %{visibility: "global"})

    assert {:ok, _} =
             Bonfire.Federate.ActivityPub.Peered.save_canonical_uri(
               mirrored,
               "https://elsewhere.local/c/mirrored"
             )

    {:ok, _} = Bonfire.Social.Pins.pin(user, mirrored, nil, to_feeds: [])

    # as the sidebar has it, so the link reads only what that load brings
    assert [{loaded, _topics}] =
             Bonfire.Classify.my_pinned_tree(user)
             |> Enum.filter(&(id(elem(&1, 0)) == mirrored.id))

    document =
      render_component(&SidebarGroupLive.render/1,
        category: loaded,
        parent_id: "sidebar",
        current_path: "/feed"
      )
      |> Floki.parse_document!()

    assert Floki.find(document, "[data-role=sidebar_group_copy_link]")
           |> Floki.attribute("href") == ["https://elsewhere.local/c/mirrored"]
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
    # the group's ActivityPub id, which opens its page in a browser
    assert Floki.attribute(copy, "href") == [
             Bonfire.Common.URIs.canonical_url(group, preload_if_needed: true)
           ]

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

  # The sidebar sits in `PersistentLive`, a sticky child of the page. Posts are published for real (the group's auto-boost broadcasts on its outbox), and the broadcast reaches that process, so the sidebar is read from the child view as it renders.
  describe "live reorder by activity" do
    setup do
      Process.put(:federating, false)
      account = fake_account!()
      me = fake_user!(account)
      other = fake_user!()

      new_group = fn name ->
        Bonfire.Classify.Simulate.fake_group!(other, %{
          name: name,
          membership: "open",
          visibility: "global",
          participation: "anyone",
          default_content_visibility: "public"
        })
      end

      a = new_group.("Alpha club")
      b = new_group.("Beta club")
      c = new_group.("Gamma club")

      t =
        Bonfire.Classify.Simulate.fake_category!(other, c, %{
          name: "Gamma topic",
          username: "gamma#{System.unique_integer([:positive])}",
          type: :topic
        })

      # A above B (newest pin first), and C followed but not pinned (joining would pin it)
      {:ok, _} = Bonfire.Social.Pins.pin(me, b, nil, to_feeds: [])
      {:ok, _} = Bonfire.Social.Pins.pin(me, a, nil, to_feeds: [])
      {:ok, _} = Bonfire.Social.Graph.Follows.follow(me, c)

      %{conn: conn(user: me, account: account), a: a, b: b, c: c, t: t, other: other, me: me}
    end

    defp group_rows(view),
      do: render(view) |> Floki.parse_document!() |> Floki.find("[data-role=sidebar-group]")

    defp row_order(view, groups) do
      ids = Enum.map(groups, & &1.id)

      for row <- group_rows(view),
          [row_id] = Floki.attribute(row, "id"),
          id <- ids,
          String.ends_with?(row_id, "-group-" <> id),
          do: id
    end

    defp row_for(view, group),
      do:
        Enum.find(group_rows(view), fn row ->
          Floki.attribute(row, "id") |> List.first() |> String.ends_with?("-group-" <> group.id)
        end)

    # a broadcast is handled in the child process, and its update to the sidebar component comes after a render asked for in between, so look again for a moment
    defp eventually(fun, tries \\ 40) do
      case fun.() do
        result when result in [nil, false, []] and tries > 0 ->
          Process.sleep(50)
          eventually(fun, tries - 1)

        result ->
          result
      end
    end

    defp order_is?(view, groups, expected) do
      eventually(fn -> row_order(view, groups) == expected end)
      row_order(view, groups)
    end

    test "a post moves its group up with a dot, adds a followed group, and dots a topic", %{
      conn: conn,
      a: a,
      b: b,
      c: c,
      t: t,
      other: other
    } do
      all = [a, b, c]

      conn
      |> visit("/dashboard")
      |> wait_async()
      |> PhoenixTest.unwrap(fn view ->
        sidebar = composer_view(view)

        # positive first: pin order, the followed unpinned group isn't there, nothing has a dot
        assert row_order(sidebar, all) == [a.id, b.id]

        assert [] ==
                 Floki.find(
                   render(sidebar) |> Floki.parse_document!(),
                   "[data-role=group-new-activity]"
                 )

        # the real path: the group's auto-boost broadcasts on its outbox, and the same message comes again below
        Phoenix.PubSub.subscribe(Bonfire.Common.PubSub, Bonfire.Social.Feeds.feed_id(:outbox, b))
        Bonfire.Classify.Simulate.fake_post_in_group!(other, b, "<p>In Beta</p>")
        assert_receive {{Bonfire.Social.Feeds, :new_activity}, _} = beta_message

        assert order_is?(sidebar, all, [b.id, a.id]) == [b.id, a.id]
        assert [_] = Floki.find(row_for(sidebar, b), "[data-role=group-new-activity]")
        assert [] == Floki.find(row_for(sidebar, a), "[data-role=group-new-activity]")

        # a post only in a topic of a followed group that isn't pinned: the group is added at the top and expanded, the topic has the dot, and the group row has none
        Bonfire.Classify.Simulate.fake_post_in_group!(other, t, "<p>In the topic</p>")
        assert order_is?(sidebar, all, [c.id, b.id, a.id]) == [c.id, b.id, a.id]

        assert eventually(fn ->
                 Floki.find(row_for(sidebar, c), "[data-role=topic-new-activity]") != []
               end)

        # let any message from the group's own outbox for the same post arrive
        Process.sleep(300)
        _ = render(sidebar)
        topics_details = Floki.find(row_for(sidebar, c), "details[id$=-topics]")
        assert [details] = topics_details
        assert Floki.attribute(details, "open") != []
        assert [] == Floki.find(row_for(sidebar, c), "[data-role=group-new-activity]")

        # a post directly in the group dots the group row as well; the group is added at the top, muted, with a button to keep it
        Bonfire.Classify.Simulate.fake_post_in_group!(other, c, "<p>In Gamma</p>")

        assert eventually(fn ->
                 Floki.find(row_for(sidebar, c), "[data-role=group-new-activity]") != []
               end)

        c_row = row_for(sidebar, c)
        assert [_] = Floki.find(c_row, "[data-role=group-new-activity]")
        assert [_] = Floki.find(c_row, "[data-unpinned]")
        assert [] == Floki.find(row_for(sidebar, b), "[data-unpinned]")
        assert [pin] = Floki.find(c_row, "[data-role=sidebar_group_pin]")
        assert Floki.attribute(pin, "phx-click") == ["Bonfire.Social.Pins:pin"]
        assert Floki.attribute(pin, "phx-value-direction") == ["up"]
        assert Floki.attribute(pin, "phx-value-id") == [c.id]
        assert Floki.attribute(pin, "phx-value-scope") == ["sidebar"]

        # (the topic row's dot is covered above)

        # one event, one effect: A moves up, and the same message about B's post again changes nothing
        Bonfire.Classify.Simulate.fake_post_in_group!(other, a, "<p>In Alpha</p>")
        assert order_is?(sidebar, all, [a.id, c.id, b.id]) == [a.id, c.id, b.id]

        send(sidebar.pid, beta_message)
        # the view handles it before this render is answered
        _ = render(sidebar)
        Process.sleep(200)
        assert row_order(sidebar, all) == [a.id, c.id, b.id]

        render(view)
      end)
    end

    test "the user's own posts neither dot nor move their groups and topics", %{
      conn: conn,
      a: a,
      b: b,
      c: c,
      t: t,
      other: other,
      me: me
    } do
      all = [a, b, c]

      conn
      |> visit("/dashboard")
      |> wait_async()
      |> PhoenixTest.unwrap(fn view ->
        sidebar = composer_view(view)
        assert row_order(sidebar, all) == [a.id, b.id]

        # my posts in the lower group, and in the topic of a followed group
        Bonfire.Classify.Simulate.fake_post_in_group!(me, b, "<p>My post in Beta</p>")
        Bonfire.Classify.Simulate.fake_post_in_group!(me, t, "<p>My post in the topic</p>")
        Process.sleep(500)
        _ = render(sidebar)

        assert row_order(sidebar, all) == [a.id, b.id]

        assert [] ==
                 Floki.find(
                   render(sidebar) |> Floki.parse_document!(),
                   "[data-role=group-new-activity]"
                 )

        assert [] ==
                 Floki.find(
                   render(sidebar) |> Floki.parse_document!(),
                   "[data-role=topic-new-activity]"
                 )

        # positive: someone else's post in the same group does move it
        Bonfire.Classify.Simulate.fake_post_in_group!(other, b, "<p>In Beta</p>")
        assert order_is?(sidebar, all, [b.id, a.id]) == [b.id, a.id]
        assert [_] = Floki.find(row_for(sidebar, b), "[data-role=group-new-activity]")

        render(view)
      end)
    end
  end

  describe "one post, announced by its group and by its topic" do
    setup do
      Process.put(:federating, false)
      account = fake_account!()
      me = fake_user!(account)
      other = fake_user!()

      new_group = fn name ->
        Bonfire.Classify.Simulate.fake_group!(other, %{
          name: name,
          membership: "open",
          visibility: "global",
          participation: "anyone",
          default_content_visibility: "public"
        })
      end

      a = new_group.("Alpha club")
      b = new_group.("Beta club")
      c = new_group.("Gamma club")

      t =
        Bonfire.Classify.Simulate.fake_category!(other, c, %{
          name: "Gamma topic",
          username: "gamma#{System.unique_integer([:positive])}",
          type: :topic
        })

      {:ok, _} = Bonfire.Social.Pins.pin(me, b, nil, to_feeds: [])
      {:ok, _} = Bonfire.Social.Pins.pin(me, a, nil, to_feeds: [])
      {:ok, _} = Bonfire.Social.Graph.Follows.follow(me, c)

      %{conn: conn(user: me, account: account), a: a, b: b, c: c, t: t, other: other}
    end

    # the sidebar is opened after the post, so both messages reach it as new, in the order the test sends them: the group's first, then the topic's
    test "the group's message first still dots the topic, and moves the group once", %{
      conn: conn,
      a: a,
      b: b,
      c: c,
      t: t,
      other: other
    } do
      all = [a, b, c]

      Phoenix.PubSub.subscribe(Bonfire.Common.PubSub, Bonfire.Social.Feeds.feed_id(:outbox, t))
      Bonfire.Classify.Simulate.fake_post_in_group!(other, t, "<p>In the topic</p>")
      assert_receive {{Bonfire.Social.Feeds, :new_activity}, data} = topic_message

      group_message =
        {{Bonfire.Social.Feeds, :new_activity},
         Keyword.update!(data, :activity, &%{&1 | subject: nil, subject_id: c.id})}

      conn
      |> visit("/dashboard")
      |> wait_async()
      |> PhoenixTest.unwrap(fn view ->
        sidebar = composer_view(view)
        assert row_order(sidebar, all) == [a.id, b.id]

        send(sidebar.pid, group_message)
        assert order_is?(sidebar, all, [c.id, a.id, b.id]) == [c.id, a.id, b.id]
        assert [] == Floki.find(row_for(sidebar, c), "[data-role=topic-new-activity]")

        # another group moves above C
        Bonfire.Classify.Simulate.fake_post_in_group!(other, a, "<p>In Alpha</p>")
        assert order_is?(sidebar, all, [a.id, c.id, b.id]) == [a.id, c.id, b.id]

        # the topic's message for the same post dots the topic, but the group isn't moved up again
        send(sidebar.pid, topic_message)

        assert eventually(fn ->
                 Floki.find(row_for(sidebar, c), "[data-role=topic-new-activity]") != []
               end)

        assert row_order(sidebar, all) == [a.id, c.id, b.id]
        render(view)
      end)
    end
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
