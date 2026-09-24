defmodule Bonfire.UI.Groups.Settings.PeopleLive do
  use Bonfire.UI.Common.Web, :stateful_component

  alias Bonfire.Classify.Categories

  prop category, :any, required: true
  prop permalink, :string, required: true
  prop member_count, :integer, default: nil
  prop moderators, :list, default: []

  data search_open?, :boolean, default: false
  data search, :string, default: ""

  data people, :list, default: []
  data cursor, :any, default: nil
  data loaded_group_id, :string, default: nil

  @doc "Loads the first five members once, preserving expanded results across parent updates."
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    socket =
      if socket.assigns.loaded_group_id != id(socket.assigns.category) do
        socket
        |> assign(people: [], loaded_group_id: id(socket.assigns.category))
        |> load_page(nil)
      else
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
