defmodule Bonfire.UI.Groups.GroupGuestInteractionTest do
  @moduledoc """
  A logged-out visitor pressing Join or Follow on a group.

  A group that federates can be joined or followed from another server, so the visitor is offered the remote interaction flow. One that doesn't federate can't: another server can't even fetch it, so the only way in is an account here, and the visitor is sent to sign in.
  """
  use Bonfire.UI.Groups.ConnCase, async: false
  @moduletag :ui

  defp group!(visibility) do
    owner = fake_user!()

    Bonfire.Classify.Simulate.fake_group!(owner, %{
      name: "Guest club",
      membership: if(visibility == "global", do: "open", else: "local:members"),
      visibility: visibility,
      participation: if(visibility == "global", do: "anyone", else: "local:contributors")
    })
  end

  # Join redirects away from the LiveView, to an absolute URL when it is remote interaction, which PhoenixTest does not follow, so the redirect target is read from the click itself
  defp join_as_guest(group) do
    {:ok, view, _html} = live(conn(), "/&#{group.character.username}")

    assert {:error, {_redirect, %{to: to}}} =
             view
             |> element("button[phx-value-component^=join_btn_]")
             |> render_click()

    to
  end

  describe "Join" do
    test "on a non-federated group sends a guest to sign in" do
      to = join_as_guest(group!("nonfederated"))

      assert to =~ "/login", "a group no other server can fetch cannot be joined from one"
      refute to =~ "remote_interaction"
    end

    # the control: the same press on a federated group does go to remote interaction, so the one above is about federation rather than guests never being offered it
    test "on a federated group offers a guest remote interaction" do
      assert join_as_guest(group!("global")) =~ "remote_interaction"
    end

    # the other server fetches `url=` to find what to join, so it has to name the group's actor, not an object route that only serves posts
    test "on a federated group points remote interaction at the group's actor" do
      group = group!("global")
      to = join_as_guest(group)

      %URI{path: path, query: query} = URI.parse(to)
      params = URI.decode_query(query || "")

      assert path == "/remote_interaction"
      assert params["type"] == "join"

      expected = Bonfire.Common.URIs.canonical_url(group)
      assert is_binary(expected) and expected != ""
      refute expected =~ "/pub/objects/"

      assert params["url"] == expected
      refute params["url"] =~ "/pub/objects/"

      # what the other server gets when it fetches that URL
      actor_json =
        build_conn()
        |> put_req_header("accept", "application/activity+json")
        |> get(URI.parse(params["url"]).path)
        |> json_response(200)

      assert actor_json["type"] == "Group"
      assert actor_json["id"] == expected
    end
  end

  # a visitor not signed in has no live socket: their click is a plain request to the LiveHandler route (`bonfire_basic.js`), carrying only the button's id, so this is the path they take
  describe "Join, as a visitor without a live socket" do
    defp join_without_socket(group) do
      conn = get(conn(), "/LiveHandler/Bonfire.UI.Groups/join_group?id=#{group.id}")

      assert conn.status in [301, 302],
             "not redirected (#{conn.status}): " <>
               (conn.resp_body
                |> Floki.parse_document!()
                |> Floki.find("main, body")
                |> Floki.text()
                |> String.split()
                |> Enum.join(" ")
                |> String.slice(0, 400))

      redirected_to(conn)
    end

    defp remote_page(to) do
      %URI{path: path, query: query} = URI.parse(to)
      {:ok, _view, html} = live(conn(), "#{path}?#{query}")
      html
    end

    test "on a federated group leads to remote interaction with the group's actor" do
      group = group!("global")
      to = join_without_socket(group)

      assert to =~ "/remote_interaction"
      assert to =~ "type=join"

      # what the page hands the visitor's instance: the group's actor, as with a live socket above
      expected = Bonfire.Common.URIs.canonical_url(group, preload_if_needed: true)
      refute expected =~ "/pub/objects/"
      assert remote_page(to) =~ ~s(value="#{expected}")
    end

    test "on a non-federated group offers only to sign in" do
      group = group!("nonfederated")
      to = join_without_socket(group)

      refute to =~ "/remote_interaction" and remote_page(to) =~ "Interact remotely",
             "a group no other server can fetch cannot be joined from one"
    end
  end

  describe "Follow" do
    test "on a non-federated group sends a guest to sign in" do
      group = group!("nonfederated")

      conn()
      |> visit("/&#{group.character.username}")
      |> wait_async()
      |> assert_has("[data-id=follow][href^='/login']")
      |> refute_has("[data-id=follow][href$='/interact/follow']")
    end

    test "on a federated group links a guest to its remote follow page" do
      group = group!("global")

      conn()
      |> visit("/&#{group.character.username}")
      |> wait_async()
      |> assert_has("[data-id=follow][href$='/interact/follow']")
    end
  end

  # the deeplink the Follow link points at has to exist, or the federated case above sends guests to a not-found page
  describe "the remote follow deeplink" do
    test "renders the remote interaction form for a group" do
      group = group!("global")

      conn()
      |> visit("/&#{group.character.username}/interact/follow")
      |> wait_async()
      |> assert_has("form", text: "Follow")
    end

    test "renders the remote interaction form for a topic" do
      owner = fake_user!()
      topic = Bonfire.Classify.Simulate.fake_category!(owner, nil, %{type: :topic})

      conn()
      |> visit("/+#{topic.character.username}/interact/follow")
      |> wait_async()
      |> assert_has("form", text: "Follow")
    end
  end
end
