defmodule Bonfire.UI.Groups.GroupNavigationTest do
  use Bonfire.UI.Groups.ConnCase, async: false
  @moduletag :ui
  doctest Bonfire.Classify.Web.GroupNavigation

  test "a pinned sidebar topic opens its group and retains the entry page" do
    account = fake_account!()
    me = fake_user!(account)
    group = Bonfire.Classify.Simulate.fake_group!(me)
    topic = Bonfire.Classify.Simulate.fake_category!(me, group, %{name: Faker.Lorem.word(), type: :topic})
    {:ok, _} = Bonfire.Social.Pins.pin(me, group, nil, to_feeds: [])
    entry = "/feed?sort=latest"

    conn(user: me, account: account)
    |> visit(Bonfire.Classify.Web.GroupNavigation.link(Bonfire.Common.URIs.path(group), entry))
    |> assert_has("[data-role='sidebar-group'] details[open]", timeout: 1_000)
    |> click_link("[data-role='sidebar-topics'] a", topic.profile.name)
    |> assert_has("[data-role='sidebar-topics'] a[aria-current='page']", text: topic.profile.name, timeout: 1_000)
    |> assert_has("#topic-parent-link[href*='group_from=%2Ffeed%3Fsort%3Dlatest']")
  end

  test "a feed entry survives the topic and parent links" do
    account = fake_account!()
    me = fake_user!(account)
    group = Bonfire.Classify.Simulate.fake_group!(me)
    topic_name = Faker.Lorem.word()
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

    assert has_element?(
             view,
             "#group-topic-mobile-#{topic.id}[href*='group_from=%2Ffeed%3Fsort%3Dlatest']"
           )

    conn(user: me, account: account)
    |> visit(Bonfire.Classify.Web.GroupNavigation.link(Bonfire.Common.URIs.path(topic), entry))
    |> click_link("#topic-parent-link", group.profile.name)
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
