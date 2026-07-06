defmodule Bonfire.UI.Groups.TopicInGroupUrlTest do
  use Bonfire.UI.Groups.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  use Bonfire.Common.Utils
  alias Bonfire.Classify.Simulate

  # A feed's "published in <topic>" link resolves a topic to a group-style URL (`/&<topic_id>`),
  # which lands on GroupLive. GroupLive should render the topic's own header (not the parent
  # group's hero) and normalise the URL in place to the canonical `/<group>/topic/<topic>`.
  test "opening a topic via a group-style URL shows the topic header (not the group hero) and normalises the URL" do
    account = fake_account!()
    me = fake_user!(account)
    group = Simulate.fake_group!(me)
    topic = Simulate.fake_category!(me, group, %{type: :topic, name: "Nested Topic"})

    # built the same way GroupLive builds the canonical URL, so it's robust to which
    # alias prefix `path/1` picks for the group
    expected_path =
      Bonfire.Common.URIs.path(group) <> "/topic/" <> topic.character.username

    conn(user: me, account: account)
    |> visit("/&#{topic.id}")
    |> wait_async()
    # the topic's own subheader (see topic_hero_live.sface: `data-id=topic_subheader`)
    |> assert_has_or_open_browser("[data-id=topic_subheader]", text: "Nested Topic")
    # the parent group's full hero (ProfileHeroFullLive: `data-id=profile_hero`) must NOT show
    |> refute_has_or_open_browser("[data-id=profile_hero]")
    # URL normalised in place (push_patch) to the nested topic-in-group path
    |> assert_path(expected_path)
  end
end
