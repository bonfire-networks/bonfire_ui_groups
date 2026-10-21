defmodule Bonfire.UI.Groups.TopicInGroupUrlTest do
  use Bonfire.UI.Groups.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  use Bonfire.Common.Utils
  alias Bonfire.Classify.Simulate

  # A feed's "published in <topic>" link resolves a topic to a group-style URL (`/&<topic_id>`),
  # which lands on GroupLive. GroupLive renders the topic inside its group's frame (the group
  # header, with the topic's chip selected) and normalises the URL in place to the canonical
  # `/<group>/topic/<topic>`.
  test "opening a topic via a group-style URL shows it in the group frame and normalises the URL" do
    account = fake_account!()
    me = fake_user!(account)
    group = Simulate.fake_group!(me)
    topic = Simulate.fake_category!(me, group, %{type: :topic, name: "Nested Topic"})

    expected_path = Bonfire.Classify.Web.GroupNavigation.topic_path(group, topic)

    conn(user: me, account: account)
    |> visit("/&#{topic.id}")
    |> wait_async()
    |> assert_has_or_open_browser("[data-id=group_hero]")
    |> assert_has_or_open_browser("[data-id=group_topics] [data-role=group-topic-current]", text: "Nested Topic")
    # URL normalised in place (push_patch) to the nested topic-in-group path
    |> assert_path(expected_path)
  end
end
