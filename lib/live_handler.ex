defmodule Bonfire.UI.Groups.LiveHandler do
  use Bonfire.UI.Common.Web, :live_handler

  alias Bonfire.Classify.Categories

  def handle_event("save_group_identity", %{"profile" => profile}, socket) do
    user = current_user_required!(socket)
    profile = Map.take(profile, ["name", "summary"])
    socket = assign(socket, :draft, profile)

    # Uploads save independently, so the modal's opening snapshot can be stale.
    with {:ok, category} <-
           Categories.get(id(socket.assigns.category), [:default, current_user: user]),
         {:ok, category} <- Categories.update(user, category, %{profile: profile}) do
      send_self(category: category)

      {:noreply,
       socket
       |> assign(category: category, draft: nil)
       |> Phoenix.LiveView.clear_flash()
       |> assign_flash(:info, l("Category updated!"))}
    else
      {:error, reason} ->
        error(reason, "Could not save group details")

        {:noreply,
         socket
         |> Phoenix.LiveView.clear_flash()
         |> assign_flash(:error, l("Could not save group details. Check the name and try again."))}
    end
  end

  def handle_event("load_settings_people", _, socket),
    do: {:noreply, Bonfire.UI.Groups.Settings.PeopleLive.load_more(socket)}

  def handle_event("open_settings_people_search", _, socket),
    do: {:noreply, assign(socket, :search_open?, true)}

  def handle_event("search_settings_people", %{"members" => %{"search" => search}}, socket),
    do: {:noreply, Bonfire.UI.Groups.Settings.PeopleLive.search(socket, search)}

  def handle_event("clear_settings_people_search", _, socket),
    do: {:noreply, Bonfire.UI.Groups.Settings.PeopleLive.search(socket, "")}

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

      send(self(), {{Bonfire.Classify.LiveHandler, :refresh_membership}, id})
      {:noreply, socket}
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

      # a guest: `current_user_or_remote_interaction/3` hands back the socket already redirecting them to sign in or to remote interaction
      %Phoenix.LiveView.Socket{} = redirecting ->
        {:noreply, redirecting}

      e ->
        error(e)
        {:noreply, assign_flash(socket, :error, l("Could not join group"))}
    end
  end

  def handle_event("leave_group", %{"id" => id} = params, socket) do
    with current_user <- current_user_required!(socket),
         {:ok, _} <- Categories.leave_group(current_user, id) do
      following? = Bonfire.Social.Graph.Follows.following?(current_user, id)
      {:noreply, socket} =
        ComponentID.send_assigns(
          e(params, "component", "join_btn_#{id}"),
          id,
          [
            my_membership: false,
            my_follow: following?
          ],
          socket
        )

      send(self(), {{Bonfire.Classify.LiveHandler, :refresh_membership}, id})

      {:noreply,
       assign_flash(socket, :info,
         if(following?,
           do: l("You left this group. You still follow its feed."),
           else: l("You left this group.")
         )
       )}
    else
      e ->
        error(e)
        {:noreply, assign_flash(socket, :error, l("Could not leave group"))}
    end
  end

  def handle_event("open_withdrawal", %{"id" => id} = params, socket) do
    Bonfire.UI.Common.ReusableModalLive.set(
      show: true,
      title_text: l("Withdraw join request?"),
      no_actions: true,
      modal_assigns: [
        modal_component: Bonfire.Classify.Web.WithdrawJoinRequestLive,
        modal_component_stateful?: true,
        object_id: id,
        button_id: e(params, "component", "join_btn_#{id}"),
        group_name: e(params, "group-name", l("this group")),
        withdrawal_error: nil
      ]
    )

    {:noreply, socket}
  end

  def handle_event("close_withdrawal", _, socket) do
    Bonfire.UI.Common.OpenModalLive.close()
    {:noreply, socket}
  end

  def handle_event("cancel_join_request", %{"id" => id} = params, socket) do
    current_user = current_user_required!(socket)

    set_button = fn my_membership ->
      Bonfire.UI.Common.OpenModalLive.close()

      Phoenix.LiveView.send_update(Bonfire.Classify.Web.JoinButtonLive,
        id: e(params, "component", "join_btn_#{id}"),
        my_membership: my_membership
      )

      {:noreply, socket}
    end

    case Categories.cancel_join_request(current_user, id) do
      # any follow is deliberately left alone: withdrawing a request to JOIN a group is not unsubscribing from its feed, and the two are separate rows precisely so one can be undone without the other
      {:ok, _} ->
        set_button.(false)

      # already approved or declined elsewhere, so there is nothing to withdraw: show where the membership stands now
      {:error, :not_found} ->
        set_button.(Map.has_key?(Categories.member_of_groups?(current_user, [id]), id))

      error ->
        error(error)
        Phoenix.LiveView.send_update(Bonfire.Classify.Web.WithdrawJoinRequestLive,
          id: "modal_component",
          withdrawal_error: l("Could not withdraw your request. Please try again.")
        )

        {:noreply, socket}
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
