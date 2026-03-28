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
         all_categories: categories,
         categories: categories,
         search_term: "",
         page_info: page_info,
         page_header_aside: [
           {Bonfire.UI.Groups.NewGroupLive,
            [
              parent_id: "explore",
              open_btn_class:
                "btn btn-outline btn-sm btn-circle lg:btn-wide btn-primary rounded-full !border-primary/30 normal-case"
            ]}
         ],
         sidebar_widgets: [
           users: [
             secondary: [
               {Bonfire.Tag.Web.WidgetTagsLive, []}
             ]
           ],
           guests: [
             secondary: [{Bonfire.Tag.Web.WidgetTagsLive, []}]
           ]
         ]
       )}
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
end
