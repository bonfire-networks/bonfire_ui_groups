defmodule Bonfire.UI.Groups.GroupGuestGateTest do
  @moduledoc """
  A group anyone can open, whose posts are for people with an account.

  The admin's move is one dropdown in the Boundaries tab: "default post visibility" goes from public to Local, on a group that already exists and already has public posts. From then on:

    * a guest still lands on the group page and sees who the group is (the hero), but in place of the feed gets an invitation to join, with the same login and sign-up destinations the login page uses (an instance with gated login, e.g. one whose members come from Ghost, points sign-up at an external URL)
    * a logged-in person sees the feed, old and new posts alike, and no invitation
    * a group whose posts stay public shows guests the feed as before

  Nothing is retroactive: old posts keep their public boundary. Whether they are still visible to a guest elsewhere is the boundary's business, not this page's. Here the invitation stands in for the whole feed, so a guest is not shown a half-empty timeline that looks like the group went quiet.
  """
  use Bonfire.UI.Groups.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  alias Bonfire.Classify.Simulate

  @gate "#group_guest_gate"

  setup do
    Process.put([:bonfire, :feed_live_update_many_preload_mode], :inline)
    Process.put(:federating, false)

    account = fake_account!()
    me = fake_user!(account)
    group = open_group(me)

    %{account: account, me: me, group: group}
  end

  test "closing the content default in the Boundaries tab gates guests without touching old posts",
       %{account: account, me: me, group: group} do
    Simulate.fake_post_in_group!(me, group, "<p>before the gate</p>")

    group = close_content_to_guests(conn(user: me, account: account), group)

    Simulate.fake_post_in_group!(me, group, "<p>after the gate</p>")

    conn()
    |> visit("/&#{group.character.username}")
    |> wait_async()
    |> assert_has("[data-id=group]", text: group.profile.name)
    |> assert_has(@gate, text: "to see this content")
    |> assert_has("#{@gate} a[href^='/login?go=']", text: "Log in")
    |> assert_has("#{@gate} a[href='/signup']", text: "Sign up")
    |> refute_has("[data-id=feed]")
    |> refute_has("[data-id=group]", text: "after the gate")
    |> refute_has("[data-id=group]", text: "before the gate")
  end

  test "a logged-in person sees the feed, old and new, and no invitation", %{
    account: account,
    me: me,
    group: group
  } do
    Simulate.fake_post_in_group!(me, group, "<p>before the gate</p>")
    group = close_content_to_guests(conn(user: me, account: account), group)
    Simulate.fake_post_in_group!(me, group, "<p>after the gate</p>")

    someone_else = fake_user!(account)

    conn(user: someone_else, account: account)
    |> visit("/&#{group.character.username}")
    |> wait_async()
    |> refute_has(@gate)
    |> assert_has("[data-id=feed]", text: "before the gate")
    |> assert_has("[data-id=feed]", text: "after the gate")
  end

  test "a group whose posts stay public shows guests the feed", %{me: me, group: group} do
    Simulate.fake_post_in_group!(me, group, "<p>open to all</p>")

    conn()
    |> visit("/&#{group.character.username}")
    |> wait_async()
    |> refute_has(@gate)
    |> assert_has("[data-id=feed]", text: "open to all")
  end

  # Where "join" leads is the instance's call, not the group's: the login page already reads these two settings (the Ghost integration writes them for a gated instance), so the invitation follows them rather than growing settings of its own.
  test "the invitation follows the instance's gated-login settings", %{
    account: account,
    me: me,
    group: group
  } do
    Process.put(
      [:bonfire_ui_me, :login, :external_signup_url],
      "https://blog.test/#/portal/signup"
    )

    Process.put(
      [:bonfire_ui_me, :login, :gated_login_message],
      "You need a Club or Comrade account to read this."
    )

    group = close_content_to_guests(conn(user: me, account: account), group)

    conn()
    |> visit("/&#{group.character.username}")
    |> wait_async()
    |> assert_has(@gate, text: "You need a Club or Comrade account to read this.")
    |> assert_has("#{@gate} a[href='https://blog.test/#/portal/signup']", text: "Sign up")
    |> refute_has("#{@gate} a[href='/signup']")
    |> assert_has("#{@gate} a[href^='/login?go=']", text: "Log in")
  end

  # `read_default_content_visibility/2` falls back to the parent group for a topic, so the gate follows without the topic storing anything.
  test "a topic inside a gated group is gated too", %{account: account, me: me, group: group} do
    group = close_content_to_guests(conn(user: me, account: account), group)
    topic = Simulate.fake_category!(me, group, %{name: "Backstage topic", type: :topic})

    conn()
    |> visit("/&#{group.character.username}/topic/#{topic.character.username}")
    |> wait_async()
    |> assert_has(@gate, text: "to see this content")
    |> refute_has("[data-id=feed]")
  end

  # The fast path: the same outcome as the Advanced dropdown, from one Fine-tune switch. The editor must also read the switch back from the group's stored default when the tab is reopened, or an admin cannot tell whether it is on.
  test "the Fine-tune switch closes new posts to guests and reads back as on", %{
    account: account,
    me: me,
    group: group
  } do
    toggle = ~s(input[phx-click="toggle_layer2"][phx-value-key="posts_need_login"])
    conn = conn(user: me, account: account)

    {:ok, view, html} = live(conn, "/&#{group.character.username}/settings/boundaries")
    assert html =~ ~s(phx-value-key="posts_need_login")

    refute view |> element(toggle) |> render() =~ "checked",
           "control: starts off on an open group"

    view |> element(toggle) |> render_click()
    view |> element("#group_settings_boundaries_form") |> render_submit()

    group =
      repo().get(Bonfire.Classify.Category, id(group))
      |> repo().maybe_preload([:settings, :character, :profile, :tree])

    assert Bonfire.Classify.Boundaries.read_default_content_visibility(group) == "local"

    assert Bonfire.Boundaries.Presets.group_dimension_slugs(group).visibility == "nonfederated",
           "the switch is about the posts: the group itself stays as visible as it was"

    {:ok, view, _html} = live(conn, "/&#{group.character.username}/settings/boundaries")
    assert view |> element(toggle) |> render() =~ "checked"

    Simulate.fake_post_in_group!(me, group, "<p>after the switch</p>")

    conn()
    |> visit("/&#{group.character.username}")
    |> wait_async()
    |> assert_has(@gate, text: "to see this content")
    |> refute_has("[data-id=group]", text: "after the switch")
  end

  # An existing group anyone, guests included, can open and read, with public posts.
  defp open_group(creator) do
    Simulate.fake_group!(creator, %{
      name: "Backstage #{System.unique_integer([:positive])}",
      membership: "local:members",
      visibility: "nonfederated",
      participation: "local:contributors",
      default_content_visibility: "nonfederated"
    })
  end

  # The admin's path: the Boundaries settings form, with only "default post visibility" moved. The editor's other hidden inputs keep the group as open as it was.
  defp close_content_to_guests(conn, group) do
    {:ok, view, _html} = live(conn, "/&#{group.character.username}/settings/boundaries")

    view
    |> element("#group_settings_boundaries_form")
    |> render_submit(%{
      "membership" => "local:members",
      "visibility" => "nonfederated",
      "participation" => "local:contributors",
      "default_content_visibility" => "local"
    })

    # `fake_group!/2` preloads `:settings`, so the struct in hand still carries the old default; `fake_post_in_group!/3` reads the default off the struct it is given. `:tree` is what creating a topic under the group needs.
    group =
      repo().get(Bonfire.Classify.Category, id(group))
      |> repo().maybe_preload([:settings, :character, :profile, :tree])

    assert Bonfire.Classify.Boundaries.read_default_content_visibility(group) == "local",
           "control: the settings form must have stored the new default before the page is checked"

    group
  end
end
