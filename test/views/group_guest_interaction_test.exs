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
