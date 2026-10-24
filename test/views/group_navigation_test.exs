defmodule Bonfire.UI.Groups.GroupNavigationTest do
  use Bonfire.UI.Groups.ConnCase, async: false
  @moduletag :ui
  doctest Bonfire.Classify.Web.GroupNavigation

  test "sidebar always shows the groups section and its group links" do
    account = fake_account!()
    me = fake_user!(account)

    group =
      Bonfire.Classify.Simulate.fake_group!(me, %{
        membership: "local:members",
        visibility: "nonfederated",
        participation: "local:contributors"
      })

    {:ok, _} = Bonfire.Social.Pins.pin(me, group, nil, to_feeds: [])
    section = "[data-role='sidebar-groups']"

    conn(user: me, account: account)
    |> visit("/group/#{group.character.username}")
    |> assert_has("#{section} [data-role='sidebar-group']", timeout: 1_000)
    # the section's heading is the link to all groups (it replaced an "All groups" item)
    |> assert_has("#{section} a[href='/groups']", text: "Groups", count: 1)
    |> assert_has("#{section} [data-role='group_tile']")
    # no collapse toggle: the group rows aren't inside a <details>
    |> refute_has("details [data-role='sidebar-group']")
  end

  # the sidebar lives in PersistentLive, not the page, and hears of pins from `Pins`
  test "the sidebar shows a group an admin pins to everyone's sidebar while it's open" do
    account = fake_account!()
    me = fake_user!(account)
    admin = fake_admin!(fake_account!())

    group =
      Bonfire.Classify.Simulate.fake_group!(admin, %{
        name: "Pinned for everyone",
        membership: "open",
        visibility: "global",
        participation: "group_members"
      })

    session =
      conn(user: me, account: account)
      |> visit("/dashboard")
      |> refute_has("[data-role='sidebar-group']", text: "Pinned for everyone")

    {:ok, _} = Bonfire.Social.Pins.pin(admin, group, :instance)

    assert_has(session, "[data-role='sidebar-group']",
      text: "Pinned for everyone",
      timeout: 1_000
    )
  end

  test "a pinned sidebar topic opens in its group and retains the entry page" do
    account = fake_account!()
    me = fake_user!(account)
    group = Bonfire.Classify.Simulate.fake_group!(me)

    topic =
      Bonfire.Classify.Simulate.fake_category!(me, group, %{
        name: Bonfire.Common.Simulation.word(),
        type: :topic
      })

    {:ok, _} = Bonfire.Social.Pins.pin(me, group, nil, to_feeds: [])
    entry = "/feed?sort=latest"

    conn(user: me, account: account)
    |> visit(Bonfire.Classify.Web.GroupNavigation.link(Bonfire.Common.URIs.path(group), entry))
    |> assert_has("[data-role='sidebar-group'] details[open]", timeout: 1_000)
    |> click_link("[data-role='sidebar-topics'] a", topic.profile.name)
    |> assert_has("[data-role='sidebar-topics'] a[aria-current='page']",
      text: topic.profile.name,
      timeout: 1_000
    )
    |> assert_has("[data-id=group_topics] [data-role=group-topic-current]",
      text: topic.profile.name
    )
    |> assert_has("#group-topic-all[href*='group_from=%2Ffeed%3Fsort%3Dlatest']")
    |> assert_has("a[href='/feed?sort=latest'][aria-label='Go back to the previous page']")
  end

  test "a feed entry survives the topic chips and the /+topic redirect" do
    account = fake_account!()
    me = fake_user!(account)
    group = Bonfire.Classify.Simulate.fake_group!(me)

    # a bare `Faker.Lorem.word()` can be "a", whose derived username is too short to be valid, so the insert failed now and then
    topic_name = "#{Faker.Lorem.word()} topic"
    topic = Bonfire.Classify.Simulate.fake_category!(me, group, %{name: topic_name, type: :topic})
    entry = "/feed?sort=latest"

    connection =
      conn(user: me, account: account)
      |> Phoenix.LiveViewTest.put_connect_params(%{
        "_live_referer" => "http://localhost:4000" <> entry
      })

    {:ok, view, _} = live(connection, "/group/#{group.character.username}")

    assert has_element?(
             view,
             "a[href='/feed?sort=latest'][aria-label='Go back to the previous page']"
           )

    assert has_element?(
             view,
             "#group-topic-link-#{topic.id}[href*='group_from=%2Ffeed%3Fsort%3Dlatest']"
           )

    # `/+topic` redirects into the group, carrying the entry page, and All patches back to the group
    conn(user: me, account: account)
    |> visit(Bonfire.Classify.Web.GroupNavigation.link(Bonfire.Common.URIs.path(topic), entry))
    |> assert_path(Bonfire.Classify.Web.GroupNavigation.topic_path(group, topic))
    |> click_link("#group-topic-all", "All")
    |> assert_path(Bonfire.Common.URIs.path(group))
    |> assert_has("a[href='/feed?sort=latest'][aria-label='Go back to the previous page']")
  end

  test "a feed entry survives members and settings round trips" do
    account = fake_account!()
    me = fake_user!(account)
    group = Bonfire.Classify.Simulate.fake_group!(me)
    entry = "/feed?sort=latest"
    group_path = Bonfire.Common.URIs.path(group)

    for {tab, selector, label} <- [
          {"members", "[data-role='group-hero-members']", "member"},
          {"settings", "a[aria-label='Manage']", "Manage"}
        ] do
      {:ok, view, _} =
        conn(user: me, account: account)
        |> live(Bonfire.Classify.Web.GroupNavigation.link(group_path, entry))

      href = Bonfire.Classify.Web.GroupNavigation.link("#{group_path}/#{tab}", entry)
      assert has_element?(view, "a[href='#{href}']")

      session =
        conn(user: me, account: account)
        |> visit(Bonfire.Classify.Web.GroupNavigation.link(group_path, entry))

      session = click_link(session, selector, label)

      parent_selector =
        if tab == "members",
          do: "#members-parent-link",
          else: "a[aria-label='Go back to the previous page']"

      session
      |> assert_has(
        "#{parent_selector}[href='#{Bonfire.Classify.Web.GroupNavigation.link(group_path, entry)}']"
      )
      |> click_link(
        parent_selector,
        if(tab == "members", do: group.profile.name, else: "Go back to the previous page")
      )
      |> assert_has("a[href='/feed?sort=latest'][aria-label='Go back to the previous page']")
    end
  end
end
