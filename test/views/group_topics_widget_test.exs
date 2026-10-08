defmodule Bonfire.UI.Groups.GroupTopicsWidgetTest do
  @moduledoc """
  The sidebar topics widget is where topics get discovered (#2389): it stays visible to whoever may create a topic even before the first one exists, and ends with a "New topic" row for them. The mobile strip under the hero only lists existing topics; there, managers find "New topic" in the More menu.
  """
  use Bonfire.UI.Groups.ConnCase, async: false
  @moduletag :ui

  alias Bonfire.Classify.Categories
  alias Bonfire.Classify.Simulate

  @widget ".sidebar-widgets .group-topics-widget"
  @widget_btn "#new_topic_widget [data-role=open_modal]"
  @mobile_strip "[data-id=main_section] [data-id=group_topics_mobile]"
  @menu_item "[data-id=profile_main_actions] [data-role=new_topic] #new_topic"

  setup do
    account = fake_account!()
    creator = fake_user!(account)

    group =
      Simulate.fake_group!(creator, %{
        name: "Neighbourhood Garden",
        membership: "open",
        visibility: "global"
      })

    {:ok, account: account, creator: creator, group: group}
  end

  defp group_view(conn, group) do
    {:ok, view, _html} = live(conn, "/group/#{group.character.username}")
    view
  end

  describe "for someone who can create topics" do
    test "an empty group shows the widget with a call to create the first topic", %{
      account: account,
      creator: creator,
      group: group
    } do
      view = group_view(conn(user: creator, account: account), group)

      assert has_element?(view, "#{@widget} [data-role=widget-heading]", "Topics")
      assert has_element?(view, "#{@widget} [data-role=widget-empty-state]", "No topics yet")
      assert has_element?(view, @widget_btn, "Create the first topic")
      # the strip under the hero only lists existing topics
      refute has_element?(view, @mobile_strip)
    end

    test "a group with topics keeps a New topic row below the topics, not in the strip",
         %{
           account: account,
           creator: creator,
           group: group
         } do
      topic = Simulate.fake_category!(creator, group, %{name: "Seed swap", type: :topic})

      view = group_view(conn(user: creator, account: account), group)

      assert has_element?(
               view,
               "#{@widget} [data-id=group_topics_nav] ~ div #{@widget_btn}",
               "New topic"
             )

      refute has_element?(view, "#{@widget} [data-role=widget-header] #new_topic_widget")

      assert has_element?(view, "#{@widget} #group-topic-link-#{id(topic)}", "Seed swap")
      refute has_element?(view, "#{@widget} [data-role=widget-empty-state]")

      assert has_element?(view, "#{@mobile_strip} #group-topic-mobile-#{id(topic)}")
      refute has_element?(view, "#{@mobile_strip} [data-role=open_modal]")
    end

    test "the hero's More menu offers New topic, since the sidebar is hidden on mobile", %{
      account: account,
      creator: creator,
      group: group
    } do
      view = group_view(conn(user: creator, account: account), group)

      assert has_element?(view, @menu_item, "New topic")
    end

    test "the widget's button opens the topic form and creates a topic in the group", %{
      account: account,
      creator: creator,
      group: group
    } do
      conn(user: creator, account: account)
      |> visit("/group/#{group.character.username}")
      |> click_button(@widget_btn, "Create the first topic")
      |> assert_has("#modal [role=dialog]", text: "Create a new topic")
      |> fill_in("Topic name", with: "Harvest calendar")
      |> click_button("[data-role=new_topic_submit]", "Create")
      |> assert_has("h1", text: "Harvest calendar")

      assert [%{profile: %{name: "Harvest calendar"}}] = group_topics(group, creator)
    end
  end

  describe "for someone who cannot create topics" do
    test "a member sees nothing for an empty group", %{account: account, group: group} do
      member = fake_user!(account)
      {:ok, _} = Categories.join_and_follow_group(member, group)

      view = group_view(conn(user: member, account: account), group)

      refute has_element?(view, @widget)
      refute has_element?(view, "#new_topic_widget")
      refute has_element?(view, "#new_topic")
    end

    test "a member sees existing topics but no New topic button", %{
      account: account,
      creator: creator,
      group: group
    } do
      topic = Simulate.fake_category!(creator, group, %{name: "Seed swap", type: :topic})
      member = fake_user!(account)
      {:ok, _} = Categories.join_and_follow_group(member, group)

      view = group_view(conn(user: member, account: account), group)

      assert has_element?(view, "#{@widget} #group-topic-link-#{id(topic)}", "Seed swap")
      refute has_element?(view, "#new_topic_widget")
      refute has_element?(view, "#new_topic")
      # the hero's More menu used to list it for anyone (`module=` where `:if=` was meant)
      refute has_element?(view, "[data-id=profile_main_actions] #new_topic")
    end

    test "a guest gets no New topic button", %{creator: creator, group: group} do
      Simulate.fake_category!(creator, group, %{name: "Seed swap", type: :topic})

      view = group_view(conn(), group)

      refute has_element?(view, "#new_topic_widget")
      refute has_element?(view, "#new_topic")
    end
  end

  test "a topic page doesn't offer an empty topics widget", %{
    account: account,
    creator: creator,
    group: group
  } do
    topic = Simulate.fake_category!(creator, group, %{name: "Seed swap", type: :topic})

    {:ok, view, _html} =
      live(conn(user: creator, account: account), Bonfire.Common.URIs.path(topic))

    refute has_element?(view, "#{@widget} [data-role=widget-empty-state]")
    refute has_element?(view, "#new_topic_widget")
  end

  defp group_topics(group, user) do
    Categories.list_tree(
      [:default, parent_category: id(group), tree_max_depth: 1, preload: :profile],
      current_user: user
    )
    |> e(:edges, [])
  end
end
