defmodule Bonfire.UI.Groups.Settings.ModeratorsLive do
  @moduledoc """
  Manages a group's moderators: lists current moderators and (for users who can
  `:mediate` the group) lets them promote a user to moderator or demote one.

  Adding/removing is delegated to `Bonfire.Classify.Categories.add_moderator/4`
  and `remove_moderator/4`, which grant/remove the `:moderate` role on the group.
  """
  use Bonfire.UI.Common.Web, :stateful_component

  alias Bonfire.Classify.Categories

  prop category, :any, required: true
  # nil (not []) so an un-passed prop falls through to self-fetching the list —
  # `[] || fetch()` would short-circuit to `[]` since an empty list is truthy.
  prop moderators, :list, default: nil

  def update(assigns, socket) do
    socket = assign(socket, assigns)

    category =
      (e(assigns, :category, nil) || e(assigns(socket), :category, nil))
      # ensure `tree.custodian_id` is available so we never offer to demote the owner
      |> repo().maybe_preload(:tree)

    current_user = current_user(assigns) || current_user(socket)

    moderators =
      e(assigns, :moderators, nil) || e(assigns(socket), :moderators, nil) ||
        list_moderators(category)

    {:ok,
     socket
     |> assign(
       category: category,
       moderators: moderators,
       can_manage: Bonfire.Boundaries.can?(current_user, :mediate, category) || false,
       custodian_id: e(category, :tree, :custodian_id, nil)
     )}
  end

  # LiveSelect autocomplete search
  def handle_event("live_select_change", %{"id" => live_select_id, "text" => search}, socket)
      when is_binary(search) and byte_size(search) >= 2 do
    results =
      Bonfire.UI.Boundaries.CircleMembersLive.do_results_for_multiselect(search,
        local_only: false
      )

    maybe_send_update(LiveSelect.Component, live_select_id, options: results)
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
      user_id -> do_add_moderator(user_id, socket)
    end
  end

  def handle_event("change", _params, socket), do: {:noreply, socket}

  # Non-JS / test path (mirrors CircleMembersLive)
  def handle_event("multi_select", %{"data" => data, "text" => _text}, socket) do
    case e(input_to_atoms(data), :id, nil) do
      nil -> {:noreply, socket}
      user_id -> do_add_moderator(user_id, socket)
    end
  end

  def handle_event("multi_select", _params, socket), do: {:noreply, socket}

  def handle_event("remove_moderator", %{"id" => user_id}, socket) when is_binary(user_id) do
    category = e(assigns(socket), :category, nil)

    with {:ok, _} <-
           Categories.remove_moderator(current_user_required!(socket), category, user_id) do
      {:noreply,
       socket
       |> assign(moderators: list_moderators(category))
       |> assign_flash(:info, l("Moderator removed"))}
    else
      e ->
        error(e)
        {:noreply, assign_flash(socket, :error, l("Could not remove moderator"))}
    end
  end

  defp do_add_moderator(user_id, socket) do
    category = e(assigns(socket), :category, nil)

    with {:ok, _} <- Categories.add_moderator(current_user_required!(socket), category, user_id) do
      {:noreply,
       socket
       |> assign(moderators: list_moderators(category))
       |> assign_flash(:info, l("Moderator added"))}
    else
      e ->
        error(e)
        {:noreply, assign_flash(socket, :error, l("Could not add moderator"))}
    end
  end

  defp list_moderators(category) do
    Categories.moderators(id(category))
    |> repo().maybe_preload([:profile, :character])
  end

  defp decode_selected_id(json_string) when is_binary(json_string) do
    case Jason.decode(json_string) do
      {:ok, data} -> data["id"] || data[:id]
      _ -> nil
    end
  end

  defp decode_selected_id(_), do: nil
end
