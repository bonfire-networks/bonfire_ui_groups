defmodule Bonfire.UI.Groups.LiveHandler do
  use Bonfire.UI.Common.Web, :live_handler

  alias Bonfire.Classify.Categories

  def handle_event("join_group", %{"id" => id} = params, socket) do
    with {:ok, current_user} <- current_user_or_remote_interaction(socket, l("join"), id),
         {:ok, result} <- Categories.join_group(current_user, id) do
      ComponentID.send_assigns(
        e(params, "component", "join_btn_#{id}"),
        id,
        [my_membership: if(result.requested, do: :requested, else: result.member)],
        socket
      )
    else
      e ->
        error(e)
        {:noreply, assign_flash(socket, :error, l("Could not join group"))}
    end
  end

  def handle_event("leave_group", %{"id" => id} = params, socket) do
    with current_user <- current_user_required!(socket),
         {:ok, _} <- Categories.leave_group(current_user, id) do
      ComponentID.send_assigns(
        e(params, "component", "join_btn_#{id}"),
        id,
        [my_membership: false, my_follow: false],
        socket
      )
    else
      e ->
        error(e)
        {:noreply, assign_flash(socket, :error, l("Could not leave group"))}
    end
  end

  def handle_event("accept_join_request", %{"id" => request_id}, socket) do
    with {:ok, _} <-
           Categories.accept_join_request(current_user_required!(socket), request_id) do
      {:noreply, assign_flash(socket, :info, l("Join request accepted"))}
    else
      e ->
        error(e)
        {:noreply, assign_flash(socket, :error, l("Could not accept join request"))}
    end
  end

  def update_many(assigns_sockets, opts \\ []) do
    {first_assigns, _socket} = List.first(assigns_sockets)

    update_many_async(
      assigns_sockets,
      opts ++
        [
          skip_if_set: :my_membership,
          id: id(first_assigns),
          assigns_to_params_fn: &assigns_to_params/1,
          preload_fn: &do_preload/3
        ]
    )
  end

  defp assigns_to_params(assigns) do
    %{
      component_id: assigns.id,
      object_id: e(assigns, :object_id, nil),
      previous_value: e(assigns, :my_membership, nil)
    }
  end

  defp do_preload(list_of_components, list_of_ids, current_user) do
    my_memberships =
      if current_user,
        do: Categories.member_of_groups?(current_user, list_of_ids),
        else: %{}

    member_ids = Map.keys(my_memberships)
    remaining_ids = Enum.reject(list_of_ids, &(&1 in member_ids))

    my_requests =
      if current_user && remaining_ids != [],
        do:
          Bonfire.Social.Requests.get!(
            current_user,
            Bonfire.Data.Social.Follow,
            remaining_ids,
            preload: false,
            skip_boundary_check: true
          )
          |> Map.new(fn r -> {e(r, :edge, :object_id, nil), true} end),
        else: %{}

    Map.new(list_of_components, fn component ->
      membership =
        if(Map.get(my_requests, component.object_id), do: :requested) ||
          Map.get(my_memberships, component.object_id) ||
          component.previous_value ||
          false

      {component.component_id, %{my_membership: membership}}
    end)
  end

  def handle_event("toggle_groups_nav_visibility", _params, socket) do
    # Toggle is handled client-side by <details> natively;
    # persisting to settings is best-effort
    {:noreply, socket}
  end

  def handle_event("new", %{} = attrs, socket) do
    Bonfire.Classify.LiveHandler.new(:group, attrs, socket)
  end

  def handle_event("autocomplete", %{"input" => input}, _socket) do
    # TODO?
  end

  def handle_event("edit", _attrs, _socket) do
    # TODO?
  end
end
