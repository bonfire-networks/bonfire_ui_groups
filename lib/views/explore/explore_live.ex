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

  # declared here rather than beside "Who can create groups" in `Bonfire.UI.Groups.RuntimeConfig`, as a module declares one setting, and this is the page that reads it
  declare_settings(:select, l("Groups page opens on"),
    keys: [Bonfire.UI.Groups, :default_view],
    options: [
      automatic: l("Automatic"),
      discover: l("Discover groups"),
      feed_all: l("Latest activities from all known groups")
    ],
    default_value: :automatic,
    description:
      l("Automatic opens the latest updates from your groups if you joined any, and otherwise the groups to discover."),
    scope: :user,
    id: "groups_default_view",
    label_name: l("Groups page opens on")
  )

  @origins ~w(all local remote)
  @feed_views [:feed, :feed_all]

  # was: loaded the All groups page here, which `load_group_view/3` now loads only for the routes that show it, so a feed view loads no groups
  # def mount(_params, _session, socket) do
  #   with {categories, group_previews, page_info} <- discover_page(current_user(socket), "all") do
  def mount(_params, _session, socket) do
    {categories, group_previews, page_info} = {[], %{}, nil}

    {:ok,
       assign(socket,
         page: "groups",
         without_secondary_widgets: true,
         page_title: l("Groups"),
         back: true,
         # which of the routes' views shows: `:discover`, `:joined`, `:archived`, `:feed` or `:feed_all`
         view: nil,
         selected_tab: "discover",
         # the one membership load: the viewer's joined group ids, held for the visit. They list the Joined view and mark the directory's cards as joined, and joining or leaving here updates them (`Bonfire.UI.Groups.LiveHandler`)
         joined_group_ids: MapSet.new(Categories.joined_group_ids(current_user(socket))),
         # and, by origin, the outbox ids of the joined groups and their topics, loaded when `/groups/feed` first shows (see `groups_feed_filters/3`)
         joined_outbox_ids: %{},
         feed_name: nil,
         feed_filters: %{},
         feed_component_id: nil,
         all_categories: categories,
         categories: categories,
         group_previews: group_previews,
         search_term: "",
         group_lookup: nil,
         # set while the search index answers the search, with its own page info
         index_search: nil,
         # which search index a search reads, public or closed (checked for the viewer), switched while a term is typed
         search_index: "public",
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

  # the view comes from the route, and `tab` is no longer read. A guest has no groups of their own, so a view of them is patched to the matching view of every group, and the URL names what shows
  def handle_params(params, _uri, socket) do
    params = Map.get(params, "group_filters", params)
    origin = valid_origin(Map.get(params, "origin"))
    view = route_view(socket)

    case guest_view(view, current_user(socket)) do
      ^view ->
        socket = load_group_view(socket, view, origin)

        if view in @feed_views do
          {:noreply, socket}
        else
          filter_groups(
            socket,
            Map.get(params, "search_term", ""),
            Map.get(params, "join_filter", "all")
          )
        end

      other ->
        {:noreply, push_patch(socket, to: view_path(other, %{"origin" => origin}))}
    end
  end

  # `/groups` (and `/group`, `/&`) have no view of their own, and render the default one in place
  defp route_view(socket) do
    case socket.assigns[:live_action] do
      view when view in [:discover, :joined, :archived, :feed, :feed_all] -> view
      _ -> default_view(socket)
    end
  end

  # the user's "Groups page opens on" setting, read from the settings loaded with the session, or else the automatic choice, from the joined group ids already held: the feed of a member's groups, the directory for everyone else. Neither asks the database
  defp default_view(socket) do
    case Bonfire.Common.Settings.get([Bonfire.UI.Groups, :default_view], :automatic,
           current_user: current_user(socket)
         )
         |> to_string() do
      "discover" ->
        :discover

      "feed_all" ->
        :feed_all

      _automatic ->
        if Enum.empty?(socket.assigns.joined_group_ids), do: :discover, else: :feed
    end
  end

  defp guest_view(view, nil) when view in [:joined, :archived], do: :discover
  defp guest_view(:feed, nil), do: :feed_all
  defp guest_view(view, _user), do: view

  @doc "The route of a /groups view, with the query params that aren't at their default."
  def view_path(view, query \\ %{}) do
    path =
      case view do
        :joined -> "/groups/joined"
        :archived -> "/groups/archived"
        :feed -> "/groups/feed"
        :feed_all -> "/groups/feed/all"
        _ -> "/groups/discover"
      end

    query =
      query
      |> Enum.reject(fn {key, value} ->
        value in [nil, ""] or (key in ["origin", "join_filter"] and value == "all")
      end)
      |> Map.new()

    if query == %{}, do: path, else: "#{path}?#{URI.encode_query(query)}"
  end

  # the directory view and the feed view of the same groups, which the Groups | Latest updates switch links between. Archived has no feed
  @doc false
  def paired_view(:discover), do: :feed_all
  def paired_view(:feed_all), do: :discover
  def paired_view(:joined), do: :feed
  def paired_view(:feed), do: :joined
  def paired_view(_), do: nil

  # the view radios name a set of groups, which shows in the current mode: its list, or its feed
  defp tab_view("archived", _current), do: :archived
  defp tab_view("joined", current) when current in @feed_views, do: :feed
  defp tab_view("joined", _current), do: :joined
  defp tab_view(_discover, current) when current in @feed_views, do: :feed_all
  defp tab_view(_discover, _current), do: :discover

  defp view_tab(view) when view in [:joined, :feed], do: "joined"
  defp view_tab(:archived), do: "archived"
  defp view_tab(_), do: "discover"

  defp valid_origin(origin) when origin in @origins, do: origin
  defp valid_origin(_), do: "all"

  # a feed view loads no groups: its `FeedLive` loads the feed itself, from the preset
  defp load_group_view(socket, view, origin) when view in @feed_views do
    feed_name = if view == :feed, do: :my_groups, else: :known_groups
    feed_component_id = "groups_feed_#{view}_#{origin}"
    {socket, feed_filters} = groups_feed_filters(socket, view, origin)

    assign(socket,
      # the feed's own controls are in the sidebar's customise-feed widget, as on any feed page (see `Bonfire.UI.Social.FeedsLive`)
      without_secondary_widgets: false,
      sidebar_widgets: [
        users: [
          secondary: [
            {Bonfire.UI.Social.WidgetCustomizeFeedLive,
             [
               id: "feed_preferences_#{feed_component_id}",
               event_target: "##{feed_component_id}",
               feed_name: feed_name,
               feed_filters: feed_filters,
               # these feeds are only group activities, so switching them off would empty them
               hide_filters: [:group_activity]
             ]}
          ]
        ]
      ],
      view: view,
      selected_tab: view_tab(view),
      origin: origin,
      all_categories: [],
      categories: [],
      group_previews: %{},
      page_info: nil,
      index_search: nil,
      search_term: "",
      group_lookup: nil,
      feed_name: feed_name,
      feed_filters: feed_filters,
      feed: nil,
      loading: true,
      feed_component_id: feed_component_id
    )
  end

  # The origin menu chooses groups by where they are hosted, as in the directory, so it goes into the groups' scope rather than the feed's own `origin` filter (where each activity came from). A new origin is a new component id, so the feed reloads.
  # `/groups/feed` filters by the outboxes of the joined groups and their topics, loaded the first time it shows for an origin and held for its later pages, with `in_groups: [:feed_ids]` in place of the preset's `:joined` subquery. With no outboxes it keeps `:joined`, which then shows nothing, as empty `feed_ids` would be dropped and leave the feed unscoped
  defp groups_feed_filters(socket, :feed, origin) do
    held = socket.assigns[:joined_outbox_ids] || %{}

    outbox_ids =
      Map.get_lazy(held, origin, fn ->
        Bonfire.Common.Repo.all(
          Categories.group_outbox_ids_query({:joined, current_user(socket)}, origin_atom(origin))
        )
      end)

    socket = assign(socket, joined_outbox_ids: Map.put(held, origin, outbox_ids))

    case outbox_ids do
      [] -> {socket, %{in_groups: Enum.reject([:joined, origin_atom(origin)], &is_nil/1)}}
      ids -> {socket, %{in_groups: [:feed_ids], feed_ids: ids}}
    end
  end

  defp groups_feed_filters(socket, _feed_all, origin) do
    case origin_atom(origin) do
      nil -> {socket, %{}}
      origin -> {socket, %{in_groups: [:all, origin]}}
    end
  end

  defp load_group_view(socket, view, origin) do
    user = current_user(socket)
    joined = socket.assigns.joined_group_ids

    {categories, previews, page_info} =
      case view do
        :joined ->
          joined_groups_page(user, joined, [])

        :archived ->
          {groups, _page_info} = Classify.my_archived_groups(user)
          {categories, previews} = hydrate_group_filters(groups, user)
          {categories, previews, nil}

        :discover ->
          if socket.assigns.view == :discover and socket.assigns.origin == origin do
            {socket.assigns.all_categories, socket.assigns.group_previews,
             socket.assigns.page_info}
          else
            discover_page(user, joined, origin)
          end
      end

    assign(socket,
      without_secondary_widgets: true,
      sidebar_widgets: [],
      view: view,
      selected_tab: view_tab(view),
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
      |> load_group_view(:archived, socket.assigns.origin)
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

    socket =
      assign(socket,
        search_index:
          if(Map.get(params, "index", socket.assigns.search_index) == "closed",
            do: "closed",
            else: "public"
          )
      )

    view = tab_view(Map.get(params, "tab", socket.assigns.selected_tab), socket.assigns.view)
    origin = valid_origin(Map.get(params, "origin", socket.assigns.origin))

    # the view and origin change which groups are loaded, so they go through the URL (and `handle_params`) to stay shareable
    cond do
      view != socket.assigns.view or origin != socket.assigns.origin ->
        query =
          if view in @feed_views,
            do: %{"origin" => origin},
            else: %{"search_term" => search_term, "join_filter" => join_filter, "origin" => origin}

        {:noreply, push_patch(socket, to: view_path(view, query))}

      view in @feed_views ->
        {:noreply, socket}

      true ->
        filter_groups(socket, search_term, join_filter)
    end
  end

  # under a search the index answered, "Load more" pages through its hits, on All groups and Joined alike
  def handle_event("load_more", attrs, %{assigns: %{index_search: %{}}} = socket) do
    offset =
      case Integer.parse(to_string(e(attrs, "after", "0"))) do
        {offset, ""} -> offset
        _ -> 0
      end

    case index_search(socket, socket.assigns.search_term, offset) do
      {found, previews, page_info} ->
        previews = Map.merge(socket.assigns.group_previews, previews)

        categories =
          (socket.assigns.categories ++ found)
          |> Enum.uniq_by(fn {group, _} -> id(group) end)

        {:noreply,
         assign(socket,
           categories: categories,
           group_previews: previews,
           index_search: %{page_info: page_info}
         )}

      nil ->
        {:noreply, socket}
    end
  end

  def handle_event("load_more", %{"context" => "joined"} = attrs, socket) do
    {new_groups, previews, page_info} =
      joined_groups_page(current_user(socket), socket.assigns.joined_group_ids,
        after: e(attrs, "after", nil)
      )

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
           discover_page(
             current_user(socket),
             socket.assigns.joined_group_ids,
             socket.assigns.origin,
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
    socket = maybe_look_up_group(socket, search_term)

    case index_search(socket, search_term, 0) do
      {found, previews, page_info} ->
        # the index already matched the term, the origin and the view. The joining-policy menu gives way to the public/private switch while a term is typed, so its filter doesn't apply then (it is kept for when the term is cleared)
        previews = Map.merge(socket.assigns.group_previews, previews)

        {:noreply,
         socket
         |> assign(
           search_term: search_term,
           join_filter: join_filter,
           group_previews: previews,
           index_search: %{page_info: page_info}
         )
         |> assign_with_looked_up_group(found)}

      nil ->
        categories =
          filter_categories(
            socket.assigns.all_categories,
            search_term,
            join_filter,
            socket.assigns.origin,
            socket.assigns.group_previews
          )

        {:noreply,
         socket
         |> assign(search_term: search_term, join_filter: join_filter, index_search: nil)
         |> assign_with_looked_up_group(categories)}
    end
  end

  # With a search index, a search on All groups asks it, so it finds every matching group rather than those on the loaded page, and pages through its hits. A topic's hit stands for its group, so a group is found by its topics' names as the in-memory filter finds it. Returns nil with no index (and on Archived, whose groups are taken out of it), and the caller filters the loaded groups instead.
  defp index_search(socket, search_term, offset) do
    tab = socket.assigns.selected_tab
    origin = socket.assigns.origin
    user = current_user(socket)

    # Joined searches as with no index (the loaded groups, filtered here): its groups are the viewer's own, public and members-only alike, which are in different indexes, so one index would miss some
    # with true <- search_term != "" and tab in ["discover", "joined"],
    with true <- search_term != "" and tab == "discover",
         %{edges: hits, page_info: page_info} <-
           Categories.search_groups(search_term,
             current_user: user,
             origin: origin_atom(origin),
             joined: tab == "joined",
             index: socket.assigns.search_index,
             offset: offset
           ) do
      {categories, previews} =
        hits
        |> groups_for_hits(user, origin)
        |> hydrate_group_previews(user, true, socket.assigns.joined_group_ids)

      {categories, previews, page_info}
    else
      _ -> nil
    end
  end

  # each hit's group, in the hits' order and once: a group stands for itself and a topic for its parent group, which is loaded (in one query) when it isn't among the hits
  defp groups_for_hits(hits, user, origin) do
    group_id = fn hit ->
      if e(hit, :type, nil) == :group, do: id(hit), else: e(hit, :tree, :parent_id, nil)
    end

    found = hits |> Enum.filter(&(e(&1, :type, nil) == :group)) |> Map.new(&{id(&1), &1})
    ordered_ids = hits |> Enum.map(group_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    parents =
      case ordered_ids -- Map.keys(found) do
        [] ->
          %{}

        missing ->
          case Categories.list(
                 [:default, type: :group, id: missing] ++ origin_filters(origin),
                 current_user: user
               ) do
            %{edges: groups} -> Map.new(groups, &{id(&1), &1})
            _ -> %{}
          end
      end

    Enum.flat_map(ordered_ids, &List.wrap(found[&1] || parents[&1]))
  end

  defp origin_atom("local"), do: :local
  defp origin_atom("remote"), do: :remote
  defp origin_atom(_), do: nil

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
        joined = socket.assigns.joined_group_ids

        socket
        |> assign(group_lookup: %{q: search_term, status: :searching})
        |> start_async(:group_lookup, fn -> look_up_group(search_term, current_user, joined) end)

      true ->
        assign(socket, group_lookup: nil)
    end
  end

  # The lookup returns whatever the handle or URL names, so anything but a group is reported as such. A group is then loaded as the list loads its groups, boundary-checked for `current_user`, so it gets the same card and preview data. Federation is an optional extension, so without it the lookup finds nothing rather than breaking the page.
  defp look_up_group(q, current_user, joined) do
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
      {categories, previews} = hydrate_group_previews([group], current_user, true, joined)
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

  # `joined` is the page's held set of the viewer's group ids, which marks the cards as joined with no query; without it (the carousel widget), membership is checked for these groups
  defp hydrate_group_previews(groups, current_user, topics? \\ true, joined \\ nil) do
    {categories, dimensions} = hydrate_group_filters(groups, current_user, topics?)
    member_counts = Categories.member_counts(groups)

    memberships =
      cond do
        is_struct(joined, MapSet) ->
          Map.new(joined, &{&1, true})

        current_user ->
          group_ids = Enum.map(groups, &id/1)
          Categories.member_of_groups?(current_user, group_ids)

        true ->
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

  defp discover_page(user, joined, origin, opts \\ []) do
    %{edges: groups, page_info: page_info} =
      Categories.list_tree(
        [:default, type: :group, tree_max_depth: 1, preload: :follow_count] ++
          origin_filters(origin),
        Keyword.merge([current_user: user], opts)
      )

    {categories, previews} = hydrate_group_previews(groups, user, true, joined)
    {categories, previews, page_info}
  end

  defp origin_filters("local"), do: [:local]
  defp origin_filters("remote"), do: [:remote]
  defp origin_filters(_), do: []

  # listed by the held ids, so the members circles aren't asked again; no ids, no query
  defp joined_groups_page(user, joined, opts) do
    if Enum.empty?(joined) do
      {[], %{}, nil}
    else
      %{edges: groups, page_info: page_info} =
        Categories.list_joined_groups(user, Keyword.put(opts, :ids, joined))

      {groups, previews} = hydrate_group_previews(groups, user, true, joined)

      {groups, previews, page_info}
    end
  end
end
