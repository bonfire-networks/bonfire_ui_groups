defmodule Bonfire.UI.Groups.SavedGroupFeedTest do
  @moduledoc """
  A custom feed saved from a group feed keeps the feed it came from: from `/feed/my_groups` or `/groups/feed` it shows the groups the reader is a member of when they open it, including groups joined after saving, and from `/feed/known_groups` or `/groups/feed/all` every group's posts. What a save stores is the reader's choice of groups, not the outbox ids the page worked out for them.
  """
  use Bonfire.UI.Groups.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  alias Bonfire.Classify.Categories
  alias Bonfire.Classify.Simulate

  # open and public, since a group made with no dimensions reviews joins and would leave the join a request
  @open_group %{
    membership: "open",
    visibility: "global",
    participation: "anyone",
    default_content_visibility: "public"
  }

  setup do
    Process.put([:bonfire, :feed_live_update_many_preload_mode], :inline)
    Process.put(:federating, false)

    account = fake_account!()
    me = fake_user!(account)
    owner = fake_user!()

    group_a = Simulate.fake_group!(owner, Map.put(@open_group, :name, "Joined Saved Group"))
    group_b = Simulate.fake_group!(owner, Map.put(@open_group, :name, "Other Saved Group"))

    {:ok, _} = Categories.join_group(me, group_a)

    Simulate.fake_post_in_group!(owner, group_a, "<p>A post in the joined group</p>")
    Simulate.fake_post_in_group!(owner, group_b, "<p>A post in the other group</p>")

    Bonfire.Posts.Fake.fake_post!(owner, "public", %{
      post_content: %{html_body: "A plain post outside any group"}
    })

    %{account: account, me: me, owner: owner}
  end

  defp saved_name, do: "saved-groups-" <> to_string(System.unique_integer([:positive]))

  # a group's posts reach its outbox as the group's boosts, so the change saved is "Replies" off, which keeps them
  defp save(session, path, name) do
    session
    |> visit(path)
    |> wait_async()
    |> uncheck("Replies")
    |> wait_async()
    |> fill_in("Feed title", with: name)
    |> click_button("Save feed")
  end

  defp reopen(session, name) do
    session
    |> visit("/settings/user/feeds")
    |> visit(Bonfire.UI.Social.FeedNavigation.build_path(name))
    |> wait_async()
    |> assert_has("#feed-description-title", text: name)
  end

  defp saved_filters(me, name) do
    me = Bonfire.Common.Repo.preload(me, :settings, force: true)

    Bonfire.Social.Feeds.feed_presets(current_user: me)
    |> Enum.find_value(fn {_slug, preset} ->
      if to_string(preset[:name]) == name, do: preset[:filters]
    end)
  end

  for path <- ["/feed/my_groups", "/groups/feed"] do
    test "saved from #{path}, it shows my groups' posts", %{account: account, me: me} do
      name = saved_name()

      conn(user: me, account: account)
      |> save(unquote(path), name)
      |> reopen(name)
      |> assert_has("[data-id=feed] article", text: "A post in the joined group")
      |> refute_has("[data-id=feed] article", text: "A post in the other group")
    end
  end

  for path <- ["/feed/known_groups", "/groups/feed/all"] do
    test "saved from #{path}, it shows every group's posts", %{account: account, me: me} do
      name = saved_name()

      conn(user: me, account: account)
      |> save(unquote(path), name)
      |> reopen(name)
      |> assert_has("[data-id=feed] article", text: "A post in the joined group")
      |> assert_has("[data-id=feed] article", text: "A post in the other group")
      |> refute_has("[data-id=feed] article", text: "A plain post outside any group")
    end
  end

  test "saved from /groups/feed, it shows a group I join after saving", %{
    account: account,
    me: me,
    owner: owner
  } do
    name = saved_name()
    session = save(conn(user: me, account: account), "/groups/feed", name)

    group_c = Simulate.fake_group!(owner, Map.put(@open_group, :name, "Later Saved Group"))
    {:ok, _} = Categories.join_group(me, group_c)
    Simulate.fake_post_in_group!(owner, group_c, "<p>A post in a group joined after saving</p>")

    session
    |> reopen(name)
    |> assert_has("[data-id=feed] article", text: "A post in a group joined after saving")
    |> assert_has("[data-id=feed] article", text: "A post in the joined group")
    |> refute_has("[data-id=feed] article", text: "A post in the other group")
  end

  test "saving from /groups/feed stores my choice of groups, not their outbox ids", %{
    account: account,
    me: me
  } do
    name = saved_name()
    save(conn(user: me, account: account), "/groups/feed", name)

    filters = saved_filters(me, name)
    assert filters, "control: the feed was saved"
    assert List.wrap(filters[:in_groups]) == [:joined]
    refute filters[:feed_ids] not in [nil, []]

    local_name = saved_name()
    save(conn(user: me, account: account), "/groups/feed?origin=local", local_name)

    assert List.wrap(saved_filters(me, local_name)[:in_groups]) == [:joined, :local]
  end
end
