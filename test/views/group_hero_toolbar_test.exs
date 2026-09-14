defmodule Bonfire.UI.Groups.GroupHeroToolbarTest do
  use Bonfire.UI.Groups.ConnCase, async: false
  @moduletag :ui

  test "group toolbar keeps management together and topics in the sidebar" do
    account = fake_account!()
    me = fake_user!(account)
    group = Bonfire.Classify.Simulate.fake_group!(me, %{name: "Reading together"})
    Bonfire.Classify.Simulate.fake_category!(me, group, %{name: "Reading notes"})

    {:ok, view, _html} =
      live(conn(user: me, account: account), "/group/#{group.character.username}")

    assert has_element?(view, "[data-id=profile_main_actions] a", "Manage")
    assert has_element?(view, "[data-id=profile_main_actions] [aria-label='Unfollow group']")
    assert has_element?(view, "[data-role=group-hero-members]", "1 member")
    assert has_element?(view, "[data-role=group-hero-visibility]")
    assert has_element?(view, "[data-role=group-hero-membership]")

    assert has_element?(
             view,
             "#group-access-details-#{group.id}:not([open]) summary[aria-label='Group access details']"
           )

    for label <- ["Joining ·", "Visibility ·", "Posting ·"] do
      assert has_element?(view, "[data-role=group-access-details-content] dt", label)
    end

    assert has_element?(view, "[data-role=group-sidebar-moderators]")
    refute has_element?(view, ".sidebar-widgets", "Who can join")
    refute has_element?(view, ".sidebar-widgets", "Who can see")
    refute has_element?(view, ".sidebar-widgets", "Who can post")
    refute has_element?(view, "[data-id=profile_main_actions] a[href$='/topics']")
    assert has_element?(view, ".sidebar-widgets [data-id=group_topics_nav]", "Reading notes")
    refute has_element?(view, "[data-id=main_section] [data-id=group_topics_nav]")

    assert has_element?(
             view,
             "[data-id=main_section] [data-id=group_topics_mobile] a",
             "Reading notes"
           )

    assert has_element?(view, "#inline_composer_placeholder_open")
    refute has_element?(view, "#inline_composer_placeholder_post")
    refute has_element?(view, "#inline_composer_placeholder_continue")
  end

  test "topic links open a child topic and keep a route back to its group" do
    account = fake_account!()
    me = fake_user!(account)
    group = Bonfire.Classify.Simulate.fake_group!(me, %{name: "Reading together"})

    topic =
      Bonfire.Classify.Simulate.fake_category!(me, group, %{name: "Reading notes", type: :topic})

    conn(user: me, account: account)
    |> visit("/group/#{group.character.username}")
    |> assert_has(".sidebar-widgets [data-role=widget-heading]", text: "Topics")
    |> refute_has("[data-id=group_topics_nav] [role=tab]")
    |> refute_has("[data-id=group_topics_nav] a", text: "All")
    |> click_link("#group-topic-link-#{id(topic)}", "Reading notes")
    |> assert_has("h1", text: "Reading notes")
    |> assert_has("#topic-parent-link", text: "Reading together")
    |> click_link("#topic-parent-link", "Reading together")
    |> assert_has("a[href='/groups'][aria-label='Go back to the previous page']")
  end
end
