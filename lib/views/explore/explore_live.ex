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

  @origins ~w(all local remote)

  def mount(_params, _session, socket) do
    with {categories, group_previews, page_info} <- discover_page(current_user(socket), "all") do
      {:ok,
       assign(socket,
         page: "groups",
         without_secondary_widgets: true,
         page_title: l("Groups"),
         back: true,
         selected_tab: "discover",
         all_categories: categories,
         categories: categories,
         group_previews: group_previews,
         search_term: "",
         group_lookup: nil,
         join_filter: "all",
         origin: "all",
         page_info: page_info,
         page_header_aside: [
           {Bonfire.UI.Groups.NewGroupLive,
            [
              id: "groups_header_create",
              parent_id: "groups_header",
              header_action: true,
              open_btn_wrapper_class: "shrink-0"
            ]}
         ]
       )}
    end
  end

  def handle_params(params, _uri, socket) do
    params = Map.get(params, "group_filters", params)
    tab = Map.get(params, "tab", "discover")
    origin = valid_origin(Map.get(params, "origin"))
    socket = load_group_view(socket, tab, origin)

    filter_groups(
      socket,
      Map.get(params, "search_term", ""),
      Map.get(params, "join_filter", "all")
    )
  end

  defp valid_origin(origin) when origin in @origins, do: origin
  defp valid_origin(_), do: "all"

  defp load_group_view(socket, tab, origin) do
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
          if socket.assigns.selected_tab == "discover" and socket.assigns.origin == origin do
            {socket.assigns.all_categories, socket.assigns.group_previews,
             socket.assigns.page_info}
          else
            discover_page(current_user(socket), origin)
          end
      end

    assign(socket,
      selected_tab: tab,
      origin: origin,
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
      |> load_group_view("archived", socket.assigns.origin)
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
    origin = valid_origin(Map.get(params, "origin", socket.assigns.origin))

    # tab and origin change which groups are loaded, so they go through the URL (and `handle_params`) to stay shareable
    if tab != socket.assigns.selected_tab or origin != socket.assigns.origin do
      query =
        URI.encode_query(%{
          "tab" => tab,
          "search_term" => search_term,
          "join_filter" => join_filter,
          "origin" => origin
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
    with {new_categories, new_previews, page_info} <-
           discover_page(current_user(socket), socket.assigns.origin,
             after: e(attrs, "after", nil)
           ) do
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
        socket.assigns.origin,
        socket.assigns.group_previews
      )

    socket = maybe_look_up_group(socket, search_term)

    {:noreply,
     socket
     |> assign(search_term: search_term, join_filter: join_filter)
     |> assign_with_looked_up_group(categories)}
  end

  # A handle or URL typed on Discover is also looked up on the fediverse, as the main search does, in the background so typing doesn't wait for a remote server. The same query isn't looked up again when only the other filters change.
  defp maybe_look_up_group(socket, search_term) do
    cond do
      socket.assigns.selected_tab != "discover" or
          not Bonfire.Common.URIs.handle_or_url?(search_term) ->
        assign(socket, group_lookup: nil)

      e(socket.assigns, :group_lookup, :q, nil) == search_term ->
        socket

      socket_connected?(socket) ->
        current_user = current_user(socket)

        socket
        |> assign(group_lookup: %{q: search_term, status: :searching})
        |> start_async(:group_lookup, fn -> look_up_group(search_term, current_user) end)

      true ->
        assign(socket, group_lookup: nil)
    end
  end

  # The lookup returns whatever the handle or URL names, so anything but a group is reported as such. A group is then loaded as the list loads its groups, boundary-checked for `current_user`, so it gets the same card and preview data. Federation is an optional extension, so without it the lookup finds nothing rather than breaking the page.
  defp look_up_group(q, current_user) do
    with {:ok, found} <-
           maybe_apply(
             Bonfire.Federate.ActivityPub.AdapterUtils,
             :get_by_url_ap_id_or_username,
             [q, [user_id: id(current_user)]],
             fallback_return: nil
           ),
         {:group, %Bonfire.Classify.Category{type: :group} = found} <- {:group, found},
         {:ok, group} <-
           Categories.one([:default, preload: :follow_count, id: id(found)],
             current_user: current_user
           ) do
      {categories, previews} = hydrate_group_previews([group], current_user)
      %{q: q, status: :found, categories: categories, previews: previews}
    else
      {:group, _not_a_group} -> %{q: q, status: :not_group}
      _ -> %{q: q, status: :not_found}
    end
  end

  # A query typed since then that isn't looked up doesn't start a new lookup, so its result is dropped here rather than by LiveView
  def handle_async(:group_lookup, {:ok, %{q: q} = lookup}, socket) do
    if e(socket.assigns, :group_lookup, :q, nil) == q do
      {:noreply,
       socket
       |> assign(group_lookup: lookup)
       |> assign_with_looked_up_group(socket.assigns.categories)}
    else
      {:noreply, socket}
    end
  end

  def handle_async(:group_lookup, {:exit, reason}, socket) do
    warn(reason, "Group lookup failed")

    case socket.assigns.group_lookup do
      %{q: q} -> {:noreply, assign(socket, group_lookup: %{q: q, status: :not_found})}
      _ -> {:noreply, socket}
    end
  end

  # A group found by its handle or URL goes at the top of the list, once, whatever the other filters say, since its address was typed
  defp assign_with_looked_up_group(socket, categories) do
    case socket.assigns.group_lookup do
      %{status: :found, categories: found, previews: previews} ->
        found_ids = Enum.map(found, fn {group, _} -> id(group) end)

        assign(socket,
          categories: found ++ Enum.reject(categories, fn {group, _} -> id(group) in found_ids end),
          group_previews: Map.merge(socket.assigns.group_previews, previews)
        )

      _ ->
        assign(socket, categories: categories)
    end
  end

  defp filter_categories(categories, search_term, join_filter, origin, previews) do
    search_term = search_term |> String.trim() |> String.downcase()

    Enum.filter(categories, fn {category, children} ->
      preview = Map.get(previews, id(category), %{})

      matches_search?(category, children, search_term) and
        matches_join_filter?(preview, join_filter) and
        matches_origin?(category, origin)
    end)
  end

  # Discover already asked the database for this origin (see `discover_page/3`), this is for Joined and Archived, which list the user's own groups. `peered` comes preloaded with the character, so it costs nothing per row.
  defp matches_origin?(_category, "all"), do: true
  defp matches_origin?(category, "local"), do: Bonfire.Me.Integration.is_local?(category)
  defp matches_origin?(category, "remote"), do: !Bonfire.Me.Integration.is_local?(category)

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

  # Asks the context rather than listing membership slugs again: `Categories.join_mode/1` is what decides this, and its values are a published API contract. The one word translated here is the
  # free case, which this filter has always spelled "open", and `join_filter` goes into the query string (see the `push_patch` above), so renaming it would break links people already have.
  defp matches_join_filter?(preview, filter) when filter in ~w(open request invite) do
    case e(preview, :membership, nil) do
      membership when is_binary(membership) ->
        Bonfire.Classify.Categories.join_mode(membership) ==
          if(filter == "open", do: "free", else: filter)

      _ ->
        # the listing query left it out, so there is nothing to filter on. `join_mode/1` would go to the database for it, which is not worth doing once per row of a list
        false
    end
  end

  defp matches_join_filter?(_preview, _unknown), do: true

  @doc """
  Lists the groups `current_user` may see (boundary-checked, so for guests only the ones visible to guests), with the same card preview data the directory uses. Returns `{[{group, topics}], previews_by_group_id}`.

  Pass `topics: false` to skip loading each group's topics (one query) when the cards won't show them, and `local: true` to leave out groups federated from other instances; other opts go to `Categories.list_tree/2` (eg. `limit:`).
  """
  def list_groups_with_previews(current_user, opts \\ []) do
    {topics?, opts} = Keyword.pop(opts, :topics, true)
    {local?, opts} = Keyword.pop(opts, :local, false)

    case Categories.list_tree(
           [:default, type: :group, tree_max_depth: 1, preload: :follow_count] ++
             if(local?, do: [:local], else: []),
           Keyword.merge([current_user: current_user], opts)
         ) do
      %{edges: [_ | _] = list} -> hydrate_group_previews(list, current_user, topics?)
      _ -> {[], %{}}
    end
  end

  defp hydrate_group_filters(groups, current_user, topics? \\ true) do
    topics_by_group =
      if topics?,
        do: Categories.list_topics_for_groups(groups, current_user: current_user),
        else: %{}

    dimensions = Bonfire.Boundaries.Presets.group_listing_dimension_slugs(groups)

    categories = Enum.map(groups, &{&1, Map.get(topics_by_group, id(&1), [])})
    {categories, dimensions}
  end

  defp hydrate_group_previews(groups, current_user, topics? \\ true) do
    {categories, dimensions} = hydrate_group_filters(groups, current_user, topics?)
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

  defp discover_page(user, origin, opts \\ []) do
    %{edges: groups, page_info: page_info} =
      Categories.list_tree(
        [:default, type: :group, tree_max_depth: 1, preload: :follow_count] ++
          origin_filters(origin),
        Keyword.merge([current_user: user], opts)
      )

    {categories, previews} = hydrate_group_previews(groups, user)
    {categories, previews, page_info}
  end

  defp origin_filters("local"), do: [:local]
  defp origin_filters("remote"), do: [:remote]
  defp origin_filters(_), do: []

  defp joined_groups_page(user, opts) do
    %{edges: groups, page_info: page_info} = Categories.list_joined_groups(user, opts)

    {groups, previews} = hydrate_group_previews(groups, user)

    {groups, previews, page_info}
  end
end
