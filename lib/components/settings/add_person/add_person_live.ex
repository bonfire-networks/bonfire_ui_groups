defmodule Bonfire.UI.Groups.Settings.AddPersonLive do
  @moduledoc """
  Finds someone to give a role in a group, `:member` or `:moderator`, and gives it: the add form that Manage moderators and the settings People card share.

  The search offers only who the role's context function would accept, leaving out who already has the role: for `:member` (`Categories.add_member/4`), people on this instance; for `:moderator` (`Categories.add_moderator/4`), people on this instance, and people elsewhere who are members. After adding, it tells its `parent`, which reloads its own list.
  """
  use Bonfire.UI.Common.Web, :stateful_component

  alias Bonfire.Classify.Categories

  prop category, :any, required: true
  prop role, :atom, required: true

  @doc "The stateful component to tell once someone is added, as `{module, id}`: it gets an update with `added: user_id`"
  prop parent, :any, default: nil

  def handle_event("live_select_change", %{"id" => live_select_id, "text" => search}, socket)
      when is_binary(search) and byte_size(search) >= 2 do
    maybe_send_update(LiveSelect.Component, live_select_id,
      options: options(search, socket.assigns.role, socket.assigns.category)
    )

    {:noreply, socket}
  end

  def handle_event("live_select_change", _params, socket), do: {:noreply, socket}

  # LiveSelect single selection (via the form's phx-change)
  def handle_event(
        "change",
        %{"_target" => ["multi_select", field_name], "multi_select" => multi_select_data},
        socket
      )
      when is_map_key(multi_select_data, field_name) and
             is_binary(:erlang.map_get(field_name, multi_select_data)) and
             :erlang.map_get(field_name, multi_select_data) != "" do
    case decode_selected_id(multi_select_data[field_name]) do
      nil -> {:noreply, socket}
      user_id -> add(user_id, socket)
    end
  end

  def handle_event("change", _params, socket), do: {:noreply, socket}

  # Non-JS / test path (mirrors CircleMembersLive)
  def handle_event("multi_select", %{"data" => data, "text" => _text}, socket) do
    case e(input_to_atoms(data), :id, nil) do
      nil -> {:noreply, socket}
      user_id -> add(user_id, socket)
    end
  end

  def handle_event("multi_select", _params, socket), do: {:noreply, socket}

  @doc "Who the search offers for `role`, as LiveSelect options. Whom to leave out is one query per circle for the whole page of results, not a check per person."
  def options(search, role, category) do
    users =
      Bonfire.Me.Users.search(search)
      |> Enum.map(fn
        %Needle.Pointer{activity: %{object: user}} -> user
        other -> other
      end)
      |> repo().maybe_preload(character: [:peered])

    {local, remote} = Enum.split_with(users, &Bonfire.Social.is_local?/1)
    already = in_circle(users, role_circle(role, category))

    case role do
      :member ->
        local

      :moderator ->
        members = in_circle(remote, Categories.members_circle(category))
        local ++ Enum.filter(remote, &MapSet.member?(members, id(&1)))
    end
    |> Enum.reject(&MapSet.member?(already, id(&1)))
    |> Bonfire.UI.Boundaries.SetBoundariesLive.results_for_multiselect()
  end

  def form_id(role), do: "add_#{role}_form"
  def field_name(role), do: "#{role}_select"

  def search_label(:member), do: l("Search for someone on this instance to add as a member")
  def search_label(:moderator), do: l("Search for a user to add as moderator")

  defp role_circle(:member, category), do: Categories.members_circle(category)
  defp role_circle(:moderator, category), do: Categories.moderators_circle(category)

  defp in_circle([], _), do: MapSet.new()

  defp in_circle(users, {:ok, circle}),
    do: Bonfire.Boundaries.Circles.encircled_subset(users, circle)

  defp in_circle(_, _), do: MapSet.new()

  defp add(user_id, socket) do
    %{role: role, category: category} = socket.assigns

    case add_with_role(role, current_user_required!(socket), category, user_id) do
      {:ok, _} ->
        case socket.assigns.parent do
          {module, id} -> maybe_send_update(module, id, added: user_id)
          _ -> nil
        end

        {:noreply, assign_flash(socket, :info, added_text(role))}

      e ->
        error(e)
        {:noreply, assign_flash(socket, :error, failed_text(role))}
    end
  end

  defp add_with_role(:member, adder, category, user_id),
    do: Categories.add_member(adder, category, user_id)

  defp add_with_role(:moderator, adder, category, user_id),
    do: Categories.add_moderator(adder, category, user_id)

  defp added_text(:member), do: l("Member added")
  defp added_text(:moderator), do: l("Moderator added")

  defp failed_text(:member), do: l("Could not add member")
  defp failed_text(:moderator), do: l("Could not add moderator")

  defp decode_selected_id(json_string) when is_binary(json_string) do
    case Jason.decode(json_string) do
      {:ok, data} -> data["id"] || data[:id]
      _ -> nil
    end
  end

  defp decode_selected_id(_), do: nil
end
