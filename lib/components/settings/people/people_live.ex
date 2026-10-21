defmodule Bonfire.UI.Groups.Settings.PeopleLive do
  use Bonfire.UI.Common.Web, :stateful_component

  alias Bonfire.Classify.Categories

  prop category, :any, required: true
  prop permalink, :string, required: true
  prop member_count, :integer, default: nil
  prop moderators, :list, default: []

  data search_open?, :boolean, default: false
  data search, :string, default: ""

  @doc "Whether the viewer may add members directly (`Categories.can_add_members?/2`), worked out once per group"
  data can_add?, :boolean, default: false
  data add_open?, :boolean, default: false

  @doc "Whether the viewer may ghost, silence, block or remove members of the group (`:mediate`), worked out once per group"
  data may_moderate?, :boolean, default: false

  @doc "The visibility slug that says who can see the list (`Categories.roster_visibility_slug/1`), worked out once per group"
  data roster_visibility_slug, :string, default: nil

  data people, :list, default: []
  data cursor, :any, default: nil
  data loaded_group_id, :string, default: nil

  @doc "Loads the first five members once, preserving expanded results across parent updates."
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    socket =
      cond do
        socket.assigns.loaded_group_id != id(socket.assigns.category) ->
          socket
          |> assign(
            people: [],
            loaded_group_id: id(socket.assigns.category),
            can_add?: Categories.can_add_members?(current_user(socket), socket.assigns.category),
            may_moderate?:
              Bonfire.Boundaries.can?(current_user(socket), :mediate, socket.assigns.category),
            roster_visibility_slug: Categories.roster_visibility_slug(socket.assigns.category)
          )
          |> load_page(nil)

        # someone was just added by the shared add form (`AddPersonLive`)
        assigns[:added] ->
          socket
          |> assign(people: [], cursor: nil)
          |> load_page(nil)

        true ->
          socket
      end

    {:ok, socket}
  end

  @doc "Appends the next five members without navigating away from settings."
  def load_more(socket) do
    if socket.assigns.cursor do
      load_page(socket, socket.assigns.cursor)
    else
      socket
    end
  end

  @doc "Takes someone out of the group (`Categories.remove_member/4`) and off this list, answering whether it worked."
  def remove(socket, user_id) do
    case Categories.remove_member(
           current_user_required!(socket),
           socket.assigns.category,
           user_id
         ) do
      {:ok, _} ->
        {:ok,
         assign(socket,
           people: Enum.reject(socket.assigns.people, &(id(&1) == user_id)),
           moderators: Enum.reject(socket.assigns.moderators, &(id(&1) == user_id)),
           member_count:
             if(is_integer(socket.assigns.member_count),
               do: max(socket.assigns.member_count - 1, 0),
               else: nil
             )
         )}

      error ->
        error(error)
        {:error, error}
    end
  end

  @doc "Resets pagination when the member search changes."
  def search(socket, search) do
    socket
    |> assign(search: String.trim(search), people: [], cursor: nil)
    |> load_page(nil)
  end

  @doc "Builds the inline search form."
  def render(assigns) do
    assigns
    |> assign(form: to_form(%{"search" => assigns.search}, as: :members))
    |> render_sface()
  end

  defp load_page(socket, cursor) do
    if Bonfire.Classify.ensure_update_allowed(current_user(socket), socket.assigns.category) do
      page =
        Categories.list_members(socket.assigns.category,
          current_user: current_user(socket),
          search: socket.assigns.search,
          pagination: [limit: 5, after: cursor]
        )

      people =
        (socket.assigns.people ++ e(page, :edges, []))
        |> Enum.uniq_by(&id/1)

      assign(socket,
        people: people,
        cursor: Bonfire.UI.Common.LoadMoreLive.end_cursor(e(page, :page_info, nil))
      )
    else
      assign(socket, people: [], cursor: nil)
    end
  end
end
