defmodule Bonfire.UI.Groups.GroupTopicChipsTest do
  @moduledoc """
  A group's topics are a row of chips under the header, at every width (`Bonfire.UI.Groups.GroupTopicsNavLive`): "All", then one chip per topic, and a "New topic" button pinned at the right, outside the scrolling chips, for whoever may create one. With no topics, someone who may create one sees just the button, so the first topic is easy to start; everyone else sees no row. It replaces the sidebar Topics widget.
  """
  use Bonfire.UI.Groups.ConnCase, async: false
  @moduletag :ui

  doctest Bonfire.UI.Groups.GroupTopicsNavLive

  alias Bonfire.Classify.Categories
  alias Bonfire.Classify.Simulate

  @row "[data-id=group_hero] [data-id=group_topics]"
  @new_topic "#{@row} [data-role=group-topics-new] #new_topic_chips [data-role=open_modal]"

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

  defp group_path(group), do: "/group/#{group.character.username}"

  describe "for someone who can create topics" do
    test "an empty group shows just the New topic button", %{account: account, creator: creator, group: group} do
      conn(user: creator, account: account)
      |> visit(group_path(group))
      |> assert_has(@new_topic, text: "New topic")
      |> refute_has("#{@row} #group-topic-all")
    end

    test "a group with topics shows All, the topics, and New topic pinned outside the scrolling chips",
         %{account: account, creator: creator, group: group} do
      topic = Simulate.fake_category!(creator, group, %{name: "Seed swap", type: :topic})

      conn(user: creator, account: account)
      |> visit(group_path(group))
      |> assert_has("#{@row} #group-topic-all[aria-current=page]", text: "All")
      |> assert_has("#{@row} [data-role=group-topics-list] #group-topic-link-#{id(topic)}", text: "Seed swap")
      |> assert_has(@new_topic, text: "New topic")
      |> refute_has("#{@row} [data-role=group-topics-list] [data-role=open_modal]")
    end

    test "New topic opens the topic form and creates a topic in the group", %{
      account: account,
      creator: creator,
      group: group
    } do
      conn(user: creator, account: account)
      |> visit(group_path(group))
      |> click_button(@new_topic, "New topic")
      |> assert_has("#modal [role=dialog]", text: "Create a new topic")
      |> fill_in("Topic name", with: "Harvest calendar")
      |> click_button("[data-role=new_topic_submit]", "Create")
      |> assert_has("[data-id=topic_subheader] #topic-title", text: "Harvest calendar")

      assert [%{profile: %{name: "Harvest calendar"}}] = group_topics(group, creator)
    end
  end

  describe "for someone who cannot create topics" do
    test "a member sees no row for an empty group", %{account: account, group: group} do
      member = fake_user!(account)
      {:ok, _} = Categories.join_and_follow_group(member, group)

      conn(user: member, account: account)
      |> visit(group_path(group))
      |> refute_has(@row)
      |> refute_has("#new_topic_chips")
    end

    test "a member sees the topics but no New topic button", %{
      account: account,
      creator: creator,
      group: group
    } do
      topic = Simulate.fake_category!(creator, group, %{name: "Seed swap", type: :topic})
      member = fake_user!(account)
      {:ok, _} = Categories.join_and_follow_group(member, group)

      conn(user: member, account: account)
      |> visit(group_path(group))
      |> assert_has("#{@row} #group-topic-link-#{id(topic)}", text: "Seed swap")
      |> refute_has("#new_topic_chips")
    end

    test "a guest sees the topics but no New topic button", %{creator: creator, group: group} do
      topic = Simulate.fake_category!(creator, group, %{name: "Seed swap", type: :topic})

      conn()
      |> visit(group_path(group))
      |> assert_has("#{@row} #group-topic-link-#{id(topic)}", text: "Seed swap")
      |> refute_has("#new_topic_chips")
    end
  end

  describe "on a topic page" do
    # the chips are the group's, so New topic starts a sibling in the group, not a topic inside this one
    test "someone who can create topics gets New topic, and it creates a topic in the group", %{
      account: account,
      creator: creator,
      group: group
    } do
      topic = Simulate.fake_category!(creator, group, %{name: "Seed swap", type: :topic})

      conn(user: creator, account: account)
      |> visit(group_path(group) <> "/topic/" <> topic.character.username)
      |> click_button(@new_topic, "New topic")
      |> fill_in("Topic name", with: "Harvest calendar")
      |> click_button("[data-role=new_topic_submit]", "Create")
      |> assert_has("[data-id=topic_subheader] #topic-title", text: "Harvest calendar")

      assert ["Harvest calendar", "Seed swap"] ==
               group_topics(group, creator) |> Enum.map(&e(&1, :profile, :name, nil)) |> Enum.sort()
    end

    test "a member gets no New topic button there", %{
      account: account,
      creator: creator,
      group: group
    } do
      topic = Simulate.fake_category!(creator, group, %{name: "Seed swap", type: :topic})
      member = fake_user!(account)
      {:ok, _} = Categories.join_and_follow_group(member, group)

      conn(user: member, account: account)
      |> visit(group_path(group) <> "/topic/" <> topic.character.username)
      |> assert_has("#{@row} #group-topic-link-#{id(topic)}[aria-current=page]")
      |> refute_has("#new_topic_chips")
    end
  end

  # a topic in a group shows the row with its chip selected (`topic_in_group_frame_test.exs`); a top-level topic has no group to list topics for
  test "a top-level topic page shows no group topics row", %{account: account, creator: creator} do
    topic = Simulate.fake_category!(creator, nil, %{name: "Seed swap", type: :topic})

    conn(user: creator, account: account)
    |> visit(Bonfire.Common.URIs.path(topic))
    |> refute_has("[data-id=group_topics]")
    |> refute_has("#new_topic_chips")
  end

  defp group_topics(group, user) do
    Categories.list_tree(
      [:default, parent_category: id(group), tree_max_depth: 1, preload: :profile],
      current_user: user
    )
    |> e(:edges, [])
  end
end
