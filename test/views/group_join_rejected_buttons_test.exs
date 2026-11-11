defmodule Bonfire.UI.Groups.GroupJoinRejectedButtonsTest do
  @moduledoc """
  The Join button on the page of a group hosted elsewhere, once its host rejects the join: it reads "Joining…" while the host has not answered, and Join again after a Reject, with no pending state left.
  """
  use Bonfire.UI.Groups.ConnCase, async: false
  @moduletag :ui

  import Tesla.Mock
  alias ActivityPub.Federator.Transformer
  alias Bonfire.Classify.Categories
  alias Bonfire.Federate.ActivityPub.Simulate, as: APSimulate

  @remote_group "https://mocked.local/groups/cooks"

  setup do
    Process.put(:federating, true)

    group_json =
      APSimulate.actor_json(@remote_group, "cooks", %{"type" => "Group", "openness" => "open"})

    mock(fn
      %{method: :get, url: @remote_group} -> json(group_json)
      %{method: :post} -> %Tesla.Env{status: 202, body: ""}
      %{method: :get} -> %Tesla.Env{status: 404, body: ""}
    end)

    {:ok, group} = Bonfire.Federate.ActivityPub.Adapter.maybe_create_remote_actor(group_json)
    {:ok, group} = Categories.get(id(group), skip_boundary_check: true)

    account = fake_account!()
    me = fake_user!(account)
    {:ok, group: group, me: me, conn: conn(user: me, account: account)}
  end

  # the Follow we sent the group, which a Lemmy-style group answers instead of the Join
  defp sent_follow(user) do
    {:ok, actor} = ActivityPub.Actor.get_cached(pointer: user)

    ActivityPub.Object
    |> repo().all()
    |> Enum.find(
      &(&1.local and &1.data["type"] == "Follow" and &1.data["actor"] == actor.ap_id and
          ActivityPub.Object.get_ap_id(&1.data["object"]) == @remote_group)
    )
  end

  test "Joining… until the host answers, and Join again after it rejects", %{
    conn: conn,
    group: group,
    me: me
  } do
    assert {:ok, _} = Categories.join_and_follow_group(me, group)
    follow = sent_follow(me)
    assert follow, "control: the Follow went out"

    conn
    |> visit(Bonfire.Common.URIs.path(group))
    |> wait_async()
    |> assert_has("button", text: "Joining…")

    assert {:ok, _} =
             Transformer.handle_incoming(%{
               "@context" => "https://www.w3.org/ns/activitystreams",
               "type" => "Reject",
               "id" => "#{@remote_group}/reject/#{System.unique_integer([:positive])}",
               "actor" => @remote_group,
               "object" => follow.data["id"],
               "to" => [follow.data["actor"]]
             })

    refute Categories.member?(me, group)

    conn
    |> visit(Bonfire.Common.URIs.path(group))
    |> wait_async()
    |> assert_has("button", text: "Join", exact: true)
    |> refute_has("button", text: "Joining…")
    |> refute_has("button", text: "Pending")
  end
end
