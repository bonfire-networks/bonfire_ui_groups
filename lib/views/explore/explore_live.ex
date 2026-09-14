defmodule Bonfire.UI.Groups.ExploreLive do
  use Bonfire.UI.Common.Web, :surface_live_view
  alias Bonfire.Classify.Categories
  alias Bonfire.Classify

  declare_extension(l("Groups"),
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

  def mount(_params, _session, socket) do
    with %{edges: list, page_info: page_info} <-
           Categories.list_tree(
             [:default, type: :group, tree_max_depth: 1, preload: :follow_count],
             current_user: current_user(socket)
           ) do
      {categories, group_previews} = hydrate_group_previews(list, current_user(socket))

      {:ok,
       assign(socket,
         page: "groups",
         page_title: l("Groups"),
         back: true,
         selected_tab: "discover",
         all_categories: categories,
         categories: categories,
         group_previews: group_previews,
         search_term: "",
         join_filter: "all",
         page_info: page_info,
         page_header_aside: [
           {Bonfire.UI.Groups.NewGroupLive,
            [
              id: "groups_header_create",
              parent_id: "groups_header",
              header_action: true,
              open_btn_wrapper_class: "shrink-0"
            ]}
         ],
         sidebar_widgets: [
           users: [
             secondary: [
               {Bonfire.Tag.Web.WidgetTagsLive, []}
             ]
           ]
         ]
       )}
    end
  end

  def handle_params(params, _uri, socket) do
    params = Map.get(params, "group_filters", params)
    tab = Map.get(params, "tab", "discover")
    socket = load_group_view(socket, tab)

    filter_groups(
      socket,
      Map.get(params, "search_term", ""),
      Map.get(params, "join_filter", "all")
    )
  end

  defp load_group_view(socket, tab) do
    tab = if current_user(socket) && tab in ["joined", "archived"], do: tab, else: "discover"

    {categories, previews, page_info} =
      case tab do
        "joined" ->
          joined_groups_page(current_user(socket), [])

        "archived" ->
          {groups, _page_info} = Classify.my_archived_groups(current_user(socket))
          {categories, previews} = hydrate_group_filters(groups, current_user(socket))
          {categories, previews, nil}

        "discover" ->
          if socket.assigns.selected_tab == "discover" do
            {socket.assigns.all_categories, socket.assigns.group_previews,
             socket.assigns.page_info}
          else
            %{edges: groups, page_info: page_info} =
              Categories.list_tree(
                [:default, type: :group, tree_max_depth: 1, preload: :follow_count],
                current_user: current_user(socket)
              )

            {categories, previews} = hydrate_group_previews(groups, current_user(socket))
            {categories, previews, page_info}
          end
      end

    assign(socket,
      selected_tab: tab,
      all_categories: categories,
      group_previews: previews,
      page_info: page_info
    )
  end

  def handle_event("unarchive", %{"id" => id}, socket) do
    user = current_user_required!(socket)

    with {:ok, _category} <- Categories.unarchive(id, user) do
      socket
      |> assign_flash(:info, l("Group restored"))
      |> load_group_view("archived")
      |> filter_groups(socket.assigns.search_term, socket.assigns.join_filter)
    else
      _ ->
        {:noreply, assign_flash(socket, :error, l("Sorry, you cannot restore this group."))}
    end
  end

  def handle_event("filter_groups", params, socket) do
    params = Map.get(params, "group_filters", params)
    search_term = Map.get(params, "search_term", socket.assigns.search_term)
    join_filter = Map.get(params, "join_filter", socket.assigns.join_filter)

    tab = Map.get(params, "tab", socket.assigns.selected_tab)

    if tab != socket.assigns.selected_tab do
      query =
        URI.encode_query(%{
          "tab" => tab,
          "search_term" => search_term,
          "join_filter" => join_filter
        })

      {:noreply, push_patch(socket, to: "/groups?#{query}")}
    else
      filter_groups(socket, search_term, join_filter)
    end
  end

  def handle_event("load_more", %{"context" => "joined"} = attrs, socket) do
    {new_groups, previews, page_info} =
      joined_groups_page(current_user(socket), after: e(attrs, "after", nil))

    socket
    |> assign(
      all_categories: socket.assigns.all_categories ++ new_groups,
      group_previews: Map.merge(socket.assigns.group_previews, previews),
      page_info: page_info
    )
    |> filter_groups(socket.assigns.search_term, socket.assigns.join_filter)
  end

  def handle_event("load_more", attrs, socket) do
    with %{edges: list, page_info: page_info} <-
           Categories.list_tree(
             [:default, type: :group, tree_max_depth: 1, preload: :follow_count],
             current_user: current_user(socket),
             after: e(attrs, "after", nil)
           ) do
      {new_categories, new_previews} = hydrate_group_previews(list, current_user(socket))

      socket
      |> assign(
        all_categories: socket.assigns.all_categories ++ new_categories,
        group_previews: Map.merge(socket.assigns.group_previews, new_previews),
        page_info: page_info
      )
      |> filter_groups(socket.assigns.search_term, socket.assigns.join_filter)
    end
  end

  defp filter_groups(socket, search_term, join_filter) do
    search_term = String.trim(search_term)

    categories =
      filter_categories(
        socket.assigns.all_categories,
        search_term,
        join_filter,
        socket.assigns.group_previews
      )

    {:noreply,
     assign(socket,
       categories: categories,
       search_term: search_term,
       join_filter: join_filter
     )}
  end

  defp filter_categories(categories, search_term, join_filter, previews) do
    search_term = search_term |> String.trim() |> String.downcase()

    Enum.filter(categories, fn {category, children} ->
      preview = Map.get(previews, id(category), %{})

      matches_search?(category, children, search_term) and
        matches_join_filter?(preview, join_filter)
    end)
  end

  defp matches_search?(_category, _children, ""), do: true

  defp matches_search?(category, children, search_term) do
    [
      e(category, :profile, :name, nil),
      e(category, :profile, :summary, nil),
      e(category, :character, :username, nil)
      | Enum.map(children, &e(&1, :profile, :name, nil))
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.any?(&String.contains?(String.downcase(&1), search_term))
  end

  defp matches_join_filter?(_preview, "all"), do: true

  defp matches_join_filter?(preview, "open"),
    do: e(preview, :membership, nil) in ["open", "local:members", "archipelago:members"]

  defp matches_join_filter?(preview, "request"),
    do: e(preview, :membership, nil) == "on_request"

  defp matches_join_filter?(preview, "invite"),
    do: e(preview, :membership, nil) == "invite_only"

  defp matches_join_filter?(_preview, _unknown), do: true

  defp hydrate_group_filters(groups, current_user) do
    topics_by_group = Categories.list_topics_for_groups(groups, current_user: current_user)
    dimensions = Bonfire.Boundaries.Presets.group_listing_dimension_slugs(groups)

    categories = Enum.map(groups, &{&1, Map.get(topics_by_group, id(&1), [])})
    {categories, dimensions}
  end

  defp hydrate_group_previews(groups, current_user) do
    {categories, dimensions} = hydrate_group_filters(groups, current_user)
    member_counts = Categories.member_counts(groups)

    memberships =
      if current_user do
        group_ids = Enum.map(groups, &id/1)
        Categories.member_of_groups?(current_user, group_ids)
      else
        %{}
      end

    previews =
      Map.new(categories, fn {group, topics} ->
        group_id = id(group)
        group_dimensions = Map.get(dimensions, group_id, %{})

        preview = %{
          topics: topics,
          member_count:
            Map.get(
              member_counts,
              group_id,
              e(group, :character, :follow_count, :object_count, 0)
            ),
          joined?: Map.get(memberships, group_id, false),
          membership: e(group_dimensions, :membership, "invite_only"),
          visibility: e(group_dimensions, :visibility, nil)
        }

        {group_id, preview}
      end)

    {categories, previews}
  end

  defp joined_groups_page(user, opts) do
    {joined, page_info} = Classify.my_followed_tree(user, opts)

    groups =
      joined
      |> Enum.filter(fn {category, _children} -> e(category, :type, nil) == :group end)
      |> Enum.map(&elem(&1, 0))

    {groups, previews} = hydrate_group_previews(groups, user)

    {groups, previews, page_info}
  end
end
