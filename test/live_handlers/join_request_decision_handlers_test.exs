defmodule Bonfire.UI.Groups.JoinRequestDecisionHandlersTest do
  @moduledoc """
  The join-request decision handlers, called directly to cover stale decisions and retry behavior. Page-level rendering is covered separately in `join_request_notification_test.exs`.
  """
  use Bonfire.UI.Groups.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui
  use Bonfire.Common.E

  alias Bonfire.Classify.Simulate
  alias Bonfire.Classify.Categories
  alias Bonfire.Social.Requests

  setup do
    Process.put(:federating, false)

    creator = fake_user!()
    moderator = fake_user!()
    other_moderator = fake_user!()
    requester = fake_user!()

    group =
      Simulate.fake_group!(creator, %{
        membership: "on_request",
        visibility: "members:private",
        participation: "group_members",
        default_content_visibility: "members:private"
      })

    {:ok, _} = Categories.add_moderator(creator, group, id(moderator))
    {:ok, _} = Categories.add_moderator(creator, group, id(other_moderator))
    {:ok, %{requested: true}} = Categories.join_group(requester, group)

    {:ok,
     moderator: moderator,
     other_moderator: other_moderator,
     requester: requester,
     group: group,
     request_id: join_request_id!(requester, group, moderator)}
  end

  defp join_request_id!(requester, group, moderator) do
    assert {:ok, request} =
             Requests.get(requester, Bonfire.Boundaries.Verbs.get_id!(:join), group,
               current_user: moderator
             ),
           "control: expected a join request row"

    id(request)
  end

  defp socket_for(user, assigns \\ %{}) do
    %Phoenix.LiveView.Socket{
      assigns:
        Map.merge(
          %{flash: %{}, __changed__: %{}, current_user: user, __context__: %{current_user: user}},
          assigns
        )
    }
  end

  defp review(user, request_id, decision, status) do
    assert {:noreply, socket} =
             Bonfire.Social.Graph.Follows.LiveHandler.handle_event(
               "review_join_request",
               %{"request_id" => request_id, "decision" => decision},
               socket_for(user, %{request_status: status, request_error: nil})
             )

    socket.assigns
  end

  defp withdraw(user, group) do
    Bonfire.UI.Groups.LiveHandler.handle_event(
      "cancel_join_request",
      %{"id" => id(group), "component" => "join_btn_#{id(group)}"},
      socket_for(user)
    )
  end

  describe "a moderator reviewing a pending request" do
    test "approving marks the row approved, so Approve is gone", %{
      moderator: moderator,
      request_id: request_id,
      requester: requester,
      group: group
    } do
      assert %{request_status: :approved, request_error: nil} =
               review(moderator, request_id, "approve", :pending)

      assert Categories.member?(requester, group)
    end

    test "declining marks the row declined, which offers Approve instead", %{
      moderator: moderator,
      request_id: request_id,
      requester: requester,
      group: group
    } do
      assert %{request_status: :declined, request_error: nil} =
               review(moderator, request_id, "decline", :pending)

      refute Categories.member?(requester, group)
    end

    test "a failure that leaves the request as it was offers a retry", %{
      moderator: moderator,
      request_id: request_id
    } do
      Repatch.patch(Bonfire.Social.Graph.Follows, :accept, fn _request, _opts ->
        {:error, :simulated}
      end)

      assert %{request_status: :pending, request_error: error} =
               review(moderator, request_id, "approve", :pending)

      assert error =~ "try again"
    end
  end

  describe "a decision already made elsewhere" do
    for decision <- ["approve", "decline"] do
      test "#{decision} after another moderator approved shows the request is gone, not a retry",
           %{moderator: moderator, other_moderator: other_moderator, request_id: request_id} do
        assert {:ok, _} = Categories.accept_join_request(other_moderator, request_id)

        assert %{request_status: :unavailable, request_error: nil} =
                 review(moderator, request_id, unquote(decision), :pending)
      end
    end

    test "approve after another moderator declined still approves",
         %{moderator: moderator, other_moderator: other_moderator, request_id: request_id} do
      assert {:ok, _} = Categories.ignore_join_request(other_moderator, request_id)

      assert %{request_status: :approved, request_error: nil} =
               review(moderator, request_id, "approve", :pending)
    end

    test "Approve instead after the requester asked again doesn't offer a retry", %{
      moderator: moderator,
      requester: requester,
      group: group,
      request_id: request_id
    } do
      assert %{request_status: :declined} = review(moderator, request_id, "decline", :pending)
      {:ok, %{requested: true}} = Categories.join_group(requester, group)

      replacement_id = join_request_id!(requester, group, moderator)
      refute replacement_id == request_id

      assert %{request_status: :unavailable, request_error: nil} =
               review(moderator, request_id, "approve", :declined)

      refute Categories.member?(requester, group)
      assert join_request_id!(requester, group, moderator) == replacement_id
      assert Requests.requested?(requester, Bonfire.Boundaries.Verbs.get_id!(:join), group)
    end
  end

  describe "the requester withdrawing a request that is no longer pending" do
    for {decided, decide, member?} <- [
          {"declined", :ignore_join_request, false},
          {"approved", :accept_join_request, true}
        ] do
      test "after it was #{decided}, the dialog closes and the button shows the membership", %{
        moderator: moderator,
        requester: requester,
        group: group,
        request_id: request_id
      } do
        assert {:ok, _} = apply(Categories, unquote(decide), [moderator, request_id])

        assert {:noreply, _socket} = withdraw(requester, group)

        button_id = "join_btn_#{id(group)}"
        member? = unquote(member?)

        assert_received {:phoenix, :send_update,
                         {{Bonfire.Classify.Web.JoinButtonLive, ^button_id},
                          %{my_membership: ^member?}}}
      end
    end
  end
end
