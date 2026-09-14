defmodule Bonfire.UI.Groups.LiveHandler do
  use Bonfire.UI.Common.Web, :live_handler

  alias Bonfire.Classify.Categories

  def handle_event("filter_members", %{"members" => %{"search" => search}}, socket),
    do: {:noreply, assign(socket, :member_search, search)}

  def handle_event("clear_member_search", _, socket),
    do: {:noreply, assign(socket, :member_search, "")}

  def handle_event("filter_member_role", %{"role" => role}, socket)
      when role in ["all", "moderators"],
      do: {:noreply, assign(socket, :member_role, role)}

  def handle_event("join_group", %{"id" => id} = params, socket) do
    with {:ok, current_user} <- current_user_or_remote_interaction(socket, "join", id),
         {:ok, result} <- Categories.join_and_follow_group(current_user, id) do
      {:noreply, socket} =
        ComponentID.send_assigns(
          e(params, "component", "join_btn_#{id}"),
          id,
          # the context functions report only what they changed, so a key being absent means that half did not move
          [
            my_membership:
              if(e(result, :requested, false), do: :requested, else: e(result, :member, false)),
            # joining a group also creates a follow, so flip the sibling Follow button live
            my_follow: if(e(result, :requested, false), do: :requested, else: true)
          ],
          socket
        )

      {:noreply, maybe_refresh_can_create(socket, current_user)}
    else
      {:error, :approval_required} ->
        {:noreply,
         assign_flash(
           socket,
           :error,
           l(
             "You still follow this group. Ask a group moderator to approve your membership before rejoining."
           )
         )}

      e ->
        error(e)
        {:noreply, assign_flash(socket, :error, l("Could not join group"))}
    end
  end

  def handle_event("leave_group", %{"id" => id} = params, socket) do
    with current_user <- current_user_required!(socket),
         {:ok, _} <- Categories.leave_group(current_user, id) do
      {:noreply, socket} =
        ComponentID.send_assigns(
          e(params, "component", "join_btn_#{id}"),
          id,
          [
            my_membership: false,
            my_follow: Bonfire.Social.Graph.Follows.following?(current_user, id)
          ],
          socket
        )

      {:noreply, maybe_refresh_can_create(socket, current_user)}
    else
      e ->
        error(e)
        {:noreply, assign_flash(socket, :error, l("Could not leave group"))}
    end
  end

  def handle_event("cancel_join_request", %{"id" => id} = params, socket) do
    with current_user <- current_user_required!(socket),
         {:ok, request} <-
           Bonfire.Social.Requests.get(
             current_user,
             Bonfire.Boundaries.Verbs.get_id!(:join),
             id,
             skip_boundary_check: true
           ),
         {:ok, _} <- Bonfire.Social.Requests.ignore(request, current_user: current_user) do
      # any follow is deliberately left alone: withdrawing a request to JOIN a group is not unsubscribing from its feed, and the two are separate rows precisely so one can be undone without the other
      ComponentID.send_assigns(
        e(params, "component", "join_btn_#{id}"),
        id,
        [my_membership: false],
        socket
      )
    else
      error ->
        error(error)
        {:noreply, assign_flash(socket, :error, l("Could not cancel join request"))}
    end
  end

  # Recompute permission-derived assigns on the parent socket so sibling components
  # (e.g. `:if={@can_create_in_category}` on the composer placeholder) reactively
  # update without a manual page reload. No-op on pages without a category.
  defp maybe_refresh_can_create(
         %{assigns: %{category: %{} = category}} = socket,
         current_user
       ) do
    assign(socket,
      can_create_in_category: Bonfire.Boundaries.can?(current_user, :create, category) || false
    )
  end

  defp maybe_refresh_can_create(socket, _current_user), do: socket

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

  def handle_event("toggle_groups_nav_visibility", _params, socket) do
    debug("toggle_groups_nav_visibility")

    with {:ok, settings} <-
           Bonfire.Common.Settings.set(
             %{
               Bonfire.UI.Groups.SidebarGroupsLive => %{
                 show_groups_nav_open:
                   !Bonfire.Common.Settings.get(
                     [Bonfire.UI.Groups.SidebarGroupsLive, :show_groups_nav_open],
                     true,
                     context: assigns(socket),
                     name: l("Default Groups Nav Open"),
                     description:
                       l("Whether the group navigation sidebar should be open by default.")
                   )
               }
             },
             current_user: current_user(socket)
           ) do
      {
        :noreply,
        socket |> maybe_assign_context(settings)
      }
    end
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
