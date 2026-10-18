defmodule Bonfire.UI.Groups.GroupHeroToolbarTest do
  use Bonfire.UI.Groups.ConnCase, async: false
  @moduletag :ui

  test "a moderator's group page opens with the composer closed" do
    account = fake_account!()
    me = fake_user!(account)
    group = Bonfire.Classify.Simulate.fake_group!(me, %{name: "Reading together"})

    {:ok, view, _html} =
      live(conn(user: me, account: account), "/group/#{group.character.username}")

    assert has_element?(view, "#inline_composer_placeholder_open")
    refute has_element?(view, "#inline_composer_placeholder_post")
    refute has_element?(view, "#inline_composer_placeholder_continue")
  end

  # a topic opens inside the group's frame, so "All" is the way back, and the page's back link still leads where the visitor came from
  test "a topic chip opens the topic in the group, and All leads back to it" do
    account = fake_account!()
    me = fake_user!(account)
    group = Bonfire.Classify.Simulate.fake_group!(me, %{name: "Reading together"})

    topic =
      Bonfire.Classify.Simulate.fake_category!(me, group, %{name: "Reading notes", type: :topic})

    conn(user: me, account: account)
    |> visit("/group/#{group.character.username}")
    |> assert_has("[data-id=group_topics] #group-topic-all", text: "All")
    |> click_link("#group-topic-link-#{id(topic)}", "Reading notes")
    |> assert_has("h1", text: "Reading together", count: 1)
    |> assert_has("[data-id=topic_subheader][data-variant=compact] #topic-title", text: "Reading notes")
    |> click_link("#group-topic-all", "All")
    |> refute_has("[data-id=topic_subheader]")
    |> assert_has("a[href='/groups'][aria-label='Go back to the previous page']")
  end
end
