defmodule Bonfire.UI.Groups.GroupDiscoveryRemoteLookupTest do
  @moduledoc """
  The search on the group discovery page looks up a typed handle or URL on the fediverse, as the main search does, and shows a group it finds with the same card as the list, at the top. Plain words still only filter the groups already loaded.
  """
  # `mock_global`, since the lookup runs in the LiveView's own async task rather than the test process
  use Bonfire.UI.Groups.ConnCase, async: false
  @moduletag :ui

  import Tesla.Mock
  alias Bonfire.Classify.Simulate
  alias Bonfire.Federate.ActivityPub.Simulate, as: APSimulate

  @remote_group "https://mocked.local/c/cooks"
  @remote_person "https://mocked.local/users/dave"

  setup do
    Process.put(:federating, true)
    test_pid = self()

    actors = %{
      @remote_group =>
        APSimulate.actor_json(@remote_group, "cooks", %{
          "type" => "Group",
          "name" => "Remote cooks"
        }),
      @remote_person => APSimulate.actor_json(@remote_person, "dave", %{"name" => "Dave Person"})
    }

    webfingers = %{
      "acct:cooks@mocked.local" => @remote_group,
      "acct:dave@mocked.local" => @remote_person
    }

    mock_global(fn
      %{method: :get, url: "https://mocked.local/.well-known/webfinger" <> _ = url} ->
        send(test_pid, {:fetched, url})

        case webfingers[URI.decode_query(URI.parse(url).query || "")["resource"]] do
          nil ->
            %Tesla.Env{status: 404, body: ""}

          actor_id ->
            json(APSimulate.webfingered(actors[actor_id]["preferredUsername"], actor_id))
        end

      %{method: :get, url: url} ->
        send(test_pid, {:fetched, url})

        case actors[url] do
          nil -> %Tesla.Env{status: 404, body: ""}
          body -> json(body)
        end

      %{method: :post} ->
        %Tesla.Env{status: 202, body: ""}
    end)

    account = fake_account!()
    me = fake_user!(account)
    local_group = Simulate.fake_group!(me, %{name: "Local bakers"})

    {:ok, conn: conn(user: me, account: account), me: me, local_group: local_group}
  end

  test "typing a remote group's handle shows that group's card at the top of the list", %{
    conn: conn,
    local_group: local_group
  } do
    conn
    |> visit("/groups/discover")
    |> wait_async()
    |> assert_has("#group-preview-#{id(local_group)}")
    |> fill_in("Search groups", with: "!cooks@mocked.local")
    |> wait_async()
    |> assert_has_or_open_browser("#group-discovery-grid > :first-child", text: "Remote cooks")
    |> refute_has("[data-role=group-lookup-status]")
  end

  test "a URL that resolves to a person says it isn't a group and shows no person", %{conn: conn} do
    conn
    |> visit("/groups/discover")
    |> wait_async()
    |> fill_in("Search groups", with: @remote_person)
    |> wait_async()
    |> assert_has_or_open_browser("[data-role=group-lookup-status]", text: "isn't a group")
    |> refute_has("body", text: "Dave Person")
  end

  test "without the federation lookup, the page still loads and says no group was found", %{
    conn: conn,
    local_group: local_group
  } do
    Process.put(
      [:bonfire_federate_activitypub, Bonfire.Federate.ActivityPub.AdapterUtils, :modularity],
      :disabled
    )

    conn
    |> visit("/groups/discover")
    |> wait_async()
    |> assert_has("#group-preview-#{id(local_group)}")
    |> fill_in("Search groups", with: "!cooks@mocked.local")
    |> wait_async()
    |> assert_has_or_open_browser("[data-role=group-lookup-status]",
      text: "No group found at !cooks@mocked.local"
    )
    |> refute_has("body", text: "Remote cooks")

    refute_received {:fetched, _}
  end

  test "plain words still filter the loaded groups, without looking anything up", %{
    conn: conn,
    me: me,
    local_group: local_group
  } do
    other_group = Simulate.fake_group!(me, %{name: "Quiet readers"})

    conn
    |> visit("/groups/discover")
    |> wait_async()
    |> assert_has("#group-preview-#{id(other_group)}")
    |> fill_in("Search groups", with: "bakers")
    |> wait_async()
    |> assert_has("#group-preview-#{id(local_group)}")
    |> refute_has("#group-preview-#{id(other_group)}")
    |> refute_has("[data-role=group-lookup-status]")

    refute_received {:fetched, _}
  end
end
