defmodule Bonfire.UI.Groups.GroupDiscussionsViewOptionsTest do
  use Bonfire.UI.Groups.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  alias Bonfire.Classify.Simulate

  setup do
    # per process, so the three entries of "Latest updates" fit on one page (the test default is 2)
    Process.put([:bonfire, :default_pagination_limit], 10)

    account = fake_account!()
    me = fake_user!(account)
    group = Simulate.fake_group!(me, %{name: "View Options Group"})

    # discussion A starts first, then B, then A gets a reply: by latest activity A comes first, by start B does
    a = Simulate.fake_post_in_group!(me, group, "<p>discussion A started first</p>")
    _b = Simulate.fake_post_in_group!(me, group, "<p>discussion B started last</p>")

    {:ok, _reply} =
      Bonfire.Posts.publish(
        current_user: me,
        post_attrs: %{post_content: %{html_body: "<p>a reply to A</p>"}, reply_to_id: a.id},
        publish_in: group.id,
        boundary: Bonfire.Classify.Boundaries.read_default_content_visibility(group)
      )

    conn = conn(user: me, account: account)

    {:ok, conn: conn, group: group}
  end

  test "a member sorts the group's discussions newest first, and back to recently active", %{
    conn: conn,
    group: group
  } do
    session =
      conn
      |> visit("/&#{group.character.username}/discussions")
      |> wait_async()
      |> assert_has("[data-role=discussions_view_options]")

    assert order(session) == [:a, :b], "control: by latest activity A (replied last) comes first"

    session = session |> choose("Recent threads") |> wait_async()
    assert order(session) == [:b, :a]

    session = session |> choose("Recent replies") |> wait_async()
    assert order(session) == [:a, :b]
  end

  test "a member sorts the group's discussions by most replies", %{conn: conn, group: group} do
    session =
      conn
      |> visit("/&#{group.character.username}/discussions")
      |> wait_async()
      |> choose("Recent threads")
      |> wait_async()

    assert order(session) == [:b, :a]

    # A has a reply, B none
    session = session |> choose("Most replies") |> wait_async()
    assert order(session) == [:a, :b]
  end

  test "a member lists every post, then one entry per thread again", %{
    conn: conn,
    group: group
  } do
    session =
      conn
      |> visit("/&#{group.character.username}/discussions")
      |> wait_async()
      |> refute_has("[data-id=feed] article", text: "a reply to A")
      # threads get the discussion footer (reply counter and participants) in place of the feed's actions
      |> assert_has("[data-id=feed] article [data-role=discussion_preview_actions]")
      |> click_button("[data-role=discussions_view_options] button", "Latest updates")
      |> wait_async()
      |> assert_has("[data-id=feed] article", text: "a reply to A")
      # every post gets the feed's normal actions
      |> assert_has("[data-id=feed] article [data-id=activity_actions]")
      |> refute_has("[data-id=feed] article [data-role=discussion_preview_actions]")

    assert order(session) == [:reply, :b, :a]

    session
    |> click_button("[data-role=discussions_view_options] button", "Discussions")
    |> wait_async()
    |> refute_has("[data-id=feed] article", text: "a reply to A")
    |> assert_has("[data-id=feed] article [data-role=discussion_preview_actions]")
  end

  test "changing the sort keeps one entry per thread", %{conn: conn, group: group} do
    conn
    |> visit("/&#{group.character.username}/discussions")
    |> wait_async()
    |> choose("Recent threads")
    |> wait_async()
    |> refute_has("[data-id=feed] article", text: "a reply to A")
  end

  # which of A, B and the reply the feed lists, in order, by the first article that holds each one's text
  defp order(session) do
    PhoenixTest.unwrap(session, fn view ->
      html = Phoenix.LiveViewTest.render(view)
      send(self(), {:feed_html, html})
      html
    end)

    assert_received {:feed_html, html}

    articles =
      html
      |> Floki.parse_document!()
      |> Floki.find("[data-id=feed] article")
      |> Enum.map(&Floki.text/1)

    [a: "discussion A started first", b: "discussion B started last", reply: "a reply to A"]
    |> Enum.flat_map(fn {key, text} ->
      case Enum.find_index(articles, &(&1 =~ text and not other_entry?(key, &1))) do
        nil -> []
        index -> [{index, key}]
      end
    end)
    |> Enum.sort()
    |> Enum.map(&elem(&1, 1))
  end

  # a reply's entry quotes the post it replies to, so A's text inside the reply's entry isn't A's own entry
  defp other_entry?(:a, text), do: text =~ "a reply to A"
  defp other_entry?(_key, _text), do: false
end
