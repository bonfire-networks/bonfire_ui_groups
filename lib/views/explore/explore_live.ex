defmodule Bonfire.UI.Groups.ExploreLive do
  use Bonfire.UI.Common.Web, :surface_live_view
  alias Bonfire.Classify.Categories
  alias Bonfire.Classify

  declare_extension("Groups",
    icon: "ph:users-three-duotone",
    emoji: "🎪",
    description:
      l("Organise in groups, whether public or private, open or close, or anything in between."),
    default_nav: [
      Bonfire.UI.Groups.SidebarGroupsLive
    ]
  )

  on_mount {LivePlugs, [Bonfire.UI.Me.LivePlugs.LoadCurrentUser]}

  declare_nav_link(l("Groups"),
    page: "groups",
    icon: "ph:users-three-duotone",
    icon_active: "ph:users-three-fill"
  )

  def mount(params, session, socket) do
    with %{edges: list, page_info: page_info} <-
           Categories.list_tree(
             [:default, type: :group, tree_max_depth: 1, preload: :follow_count],
             current_user: current_user(socket)
           ) do
      categories = Enum.map(list, &{&1, []})

      {:ok,
       assign(socket,
         page: "groups",
         page_title: "Groups",
         back: true,
         selected_tab: "discover",
         all_categories: categories,
         categories: categories,
         joined_categories: [],
         joined_page_info: nil,
         archived_categories: [],
         search_term: "",
         page_info: page_info,
         page_header_aside: [
           {Bonfire.UI.Groups.NewGroupLive,
            [
              id: "explore_new_group",
              parent_id: "explore",
              open_btn_class:
                "btn btn-outline btn-sm btn-circle btn-primary !border-primary/30 normal-case"
            ]}
         ],
         sidebar_widgets: [
           users: [
             secondary: [
               {Bonfire.Tag.Web.WidgetTagsLive, []}
             ]
           ]
           #  guests: [
           #    secondary: [{Bonfire.Tag.Web.WidgetTagsLive, []}]
           #  ]
         ]
       )}
    end
  end

  def handle_params(%{"tab" => "joined"}, _uri, socket) do
    {joined_groups, page_info} = joined_groups_page(current_user(socket), [])

    {:noreply,
     assign(socket,
       selected_tab: "joined",
       joined_categories: joined_groups,
       joined_page_info: page_info
     )}
  end

  def handle_params(%{"tab" => "archived"}, _uri, socket) do
    {archived, _page_info} = Classify.my_archived_groups(current_user(socket))

    {:noreply,
     assign(socket,
       selected_tab: "archived",
       archived_categories: Enum.map(archived, &{&1, []})
     )}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, selected_tab: "discover")}
  end

  def handle_event("unarchive", %{"id" => id}, socket) do
    user = current_user_required!(socket)

    with {:ok, _category} <- Categories.unarchive(id, user) do
      {archived, _page_info} = Classify.my_archived_groups(user)

      {:noreply,
       socket
       |> assign_flash(:info, l("Group restored"))
       |> assign(archived_categories: Enum.map(archived, &{&1, []}))}
    else
      _ ->
        {:noreply, assign_flash(socket, :error, l("Sorry, you cannot restore this group."))}
    end
  end

  def handle_event("search_groups", %{"search_term" => search_term}, socket) do
    trimmed = String.trim(search_term)
    all = socket.assigns.all_categories

    filtered =
      if trimmed == "" do
        all
      else
        downcased = String.downcase(trimmed)

        Enum.filter(all, fn {category, _children} ->
          name = category |> e(:profile, :name, "") |> String.downcase()
          summary = category |> e(:profile, :summary, "") |> String.downcase()
          String.contains?(name, downcased) or String.contains?(summary, downcased)
        end)
      end

    {:noreply, assign(socket, categories: filtered, search_term: search_term)}
  end

  # Joined tab has its own load-more, keyed by the `context="joined"` the LoadMoreLive button sends —
  # it appends to `joined_categories` (not the discover list) and tracks its own cursor.
  def handle_event("load_more", %{"context" => "joined"} = attrs, socket) do
    {new_groups, page_info} =
      joined_groups_page(current_user(socket), after: e(attrs, "after", nil))

    {:noreply,
     assign(socket,
       joined_categories: socket.assigns.joined_categories ++ new_groups,
       joined_page_info: page_info
     )}
  end

  def handle_event("load_more", attrs, socket) do
    with %{edges: list, page_info: page_info} <-
           Categories.list_tree(
             [:default, type: :group, tree_max_depth: 1, preload: :follow_count],
             current_user: current_user(socket),
             after: e(attrs, "after", nil)
           ) do
      new_categories = Enum.map(list, &{&1, []})
      all = socket.assigns.all_categories ++ new_categories

      {:noreply,
       assign(socket,
         all_categories: all,
         categories: all,
         search_term: "",
         page_info: page_info
       )}
    end
  end

  defp joined_groups_page(user, opts) do
    {joined, page_info} = Classify.my_followed_tree(user, opts)

    groups =
      Enum.filter(joined, fn {category, _children} -> e(category, :type, nil) == :group end)

    {groups, page_info}
  end
end
