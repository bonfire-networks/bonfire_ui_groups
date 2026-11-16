defmodule Bonfire.UI.Groups.SidebarGroupsLive do
  use Bonfire.UI.Common.Web, :stateful_component

  declare_nav_component("Links to user's groups (and optionally topics)", exclude_from_nav: false)

  # Matches when `current_path` equals `target` exactly, or starts with `target <> "/"` so
  # nested routes (e.g. `/&games/settings`) still highlight the parent group.
  def active_link?(current_path, target)
      when is_binary(current_path) and is_binary(target) do
    current_path == target or String.starts_with?(current_path, target <> "/")
  end

  def active_link?(_, _), do: false

  defp groups(socket) do
    for {%{type: :group} = category, _children} <- e(socket.assigns, :categories, []),
        do: category
  end

  # one query for the whole list, shared by icons and join modes
  defp assign_group_dimensions(socket) do
    dims = Bonfire.Boundaries.Presets.group_listing_dimension_slugs(groups(socket))

    socket
    |> assign(
      :group_icons,
      Map.new(dims, fn {id, d} -> {id, Bonfire.Boundaries.Presets.icon_from_dims(d)} end)
    )
    |> assign(
      :join_modes,
      Map.new(dims, fn {id, d} -> {id, Bonfire.Classify.Categories.join_mode(d.membership)} end)
    )
  end

  # Admin-pinned groups can't be removed from a personal sidebar, so their row menu says so instead
  # of offering an unpin that would silently no-op. One query for the whole list.
  defp assign_instance_pins(socket) do
    assign(
      socket,
      :instance_pinned_ids,
      MapSet.new(Bonfire.Social.Pins.instance_pinned_object_ids())
    )
  end

  defp assign_memberships(socket) do
    assign(
      socket,
      :my_memberships,
      Bonfire.Classify.Categories.my_membership_states(
        current_user(socket),
        Enum.map(groups(socket), &id/1)
      )
    )
  end

  # Pulls the path once (avoids a per-link URI.parse on every render).
  defp assign_current_path(socket) do
    url = current_url(socket)
    path = is_binary(url) && (URI.parse(url).path || url)
    # the rows are patch links with the plain path, so the sidebar holds no entry page
    # params = e(socket.assigns, :__context__, :current_params, %{}) || %{}

    socket
    |> assign(:current_path, path || "")

    # |> assign(:group_return_to, Bonfire.Classify.Web.GroupNavigation.return_to(params, url))
  end

  # a pin changed (`Pins.LiveHandler.handle_info/2`), or a membership (routed via PersistentLive)
  def update(%{reload_pins: true}, socket) do
    {:ok,
     socket
     |> assign(categories: pinned_tree(current_user(socket)), unpinned_ids: MapSet.new())
     |> assign_group_dimensions()
     |> assign_instance_pins()
     |> assign_memberships()
     |> subscribe_to_activity()}
  end

  # a post in a group or topic we listen to (`Bonfire.UI.Groups.LiveHandler.handle_info/2`)
  def update(%{new_activity: %{post_id: post_id, subject_id: subject_id} = activity}, socket) do
    # the user's own posts don't dot or move their groups
    if activity[:creator_id] && activity[:creator_id] == current_user_id(socket),
      do: {:ok, socket},
      else: {:ok, bump(socket, post_id, subject_id)}
  end

  def update(assigns, %{assigns: %{categories: _}} = socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> register_for_pin_updates()
     |> assign_current_path()
     |> clear_opened()}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       categories: pinned_tree(current_user(assigns) || current_user(socket)),
       new_activity_ids: MapSet.new(),
       unpinned_ids: MapSet.new(),
       seen_post_ids: MapSet.new(),
       subscribed_feed_ids: MapSet.new()
     )
     |> assign_group_dimensions()
     |> assign_instance_pins()
     |> assign_memberships()
     |> register_for_pin_updates()
     |> subscribe_to_pins()
     |> subscribe_to_activity()
     |> assign_current_path()}
  end

  # TODO later, still open for better performance: the persisted version. On load, the order and dots would come from the newest `FeedPublish.id` per group outbox (needs a `(feed_id, id)` index) compared with what the user has seen (`FeedActivities.any_unseen?/2`), and opening a group would mark it seen, instead of this order and these dots, which only last until the page is reloaded
  # TODO later: topics under topics (only direct topics are listened to and shown)
  # TODO later: when a resync of a mirrored group's topics finds new ones, a PubSub signal could add them here (and to the topics modal), so their feeds are listened to without a reload
  # Listens to the outbox of every group and topic the sidebar shows (ids it already holds, no query), then of what the user follows that isn't pinned (one query, `Categories.followed_outbox_ids/3`), up to `max_subscriptions` in all. Each id once: a second subscription would deliver each message twice.
  defp subscribe_to_activity(socket) do
    if user = current_user(socket) do
      already = socket.assigns[:subscribed_feed_ids] || MapSet.new()
      room = max(Config.get([__MODULE__, :max_subscriptions], 500) - MapSet.size(already), 0)
      categories = e(socket.assigns, :categories, [])

      shown =
        for {category, children} <- categories,
            %{type: _} = row <- [category | Enum.map(children, &elem(&1, 0))],
            outbox_id = e(row, :character, :outbox_id, nil),
            not MapSet.member?(already, outbox_id),
            uniq: true,
            do: outbox_id

      shown = Enum.take(shown, room)

      followed =
        Bonfire.Classify.Categories.followed_outbox_ids(
          user,
          Enum.map(categories, fn {group, _} -> id(group) end),
          room - length(shown)
        )
        |> Enum.reject(&MapSet.member?(already, &1))

      feed_ids = Enum.uniq(shown ++ followed)
      PubSub.subscribe(feed_ids, socket)
      assign(socket, :subscribed_feed_ids, MapSet.union(already, MapSet.new(feed_ids)))
    else
      socket
    end
  end

  # One post, one effect per row: the group and its topic may each announce the same post (each boosts it into its own outbox), and the sidebar keeps what it has seen as `{row id, post id}`. The topic always gets its dot, whichever message comes first, and the group is moved up once per post. Only for a post the user can see, as the feeds check.
  defp bump(socket, post_id, subject_id) do
    if MapSet.member?(socket.assigns.seen_post_ids, {subject_id, post_id}) do
      socket
    else
      if Bonfire.Common.Needles.exists?([id: post_id], current_user: current_user(socket)),
        do: move_to_top(socket, subject_id, post_id),
        else: socket
    end
  end

  # the group (or the topic and its group) goes to the top with a dot, whether it is in the tree, or loaded now (one query per row, the first time it appears in the session) and shown as not pinned
  defp move_to_top(socket, subject_id, post_id) do
    categories = socket.assigns.categories

    case find_in_tree(categories, subject_id) do
      {:group, {_group, _children} = entry} ->
        put_on_top(socket, entry, [subject_id], post_id, subject_id)

      {:topic, {group, children}, {topic, _} = topic_entry} ->
        put_on_top(
          socket,
          {group, [topic_entry | Enum.reject(children, &(id(elem(&1, 0)) == id(topic)))]},
          # only the topic gets the dot: the group row expands to show it
          [subject_id],
          post_id,
          subject_id
        )

      nil ->
        add_loaded(socket, Bonfire.Classify.load_sidebar_category(subject_id), post_id)
    end
  end

  defp find_in_tree(categories, subject_id) do
    Enum.find_value(categories, fn {group, children} = entry ->
      cond do
        id(group) == subject_id ->
          {:group, entry}

        topic_entry = Enum.find(children, &(id(elem(&1, 0)) == subject_id)) ->
          {:topic, entry, topic_entry}

        true ->
          nil
      end
    end)
  end

  defp add_loaded(socket, %{type: :group} = group, post_id) do
    socket
    |> put_on_top({group, []}, [id(group)], post_id, id(group))
    |> mark_unpinned(id(group))
    |> refresh_dimensions()
  end

  defp add_loaded(socket, %{type: :topic} = topic, post_id) do
    parent_id = e(topic, :tree, :parent_id, nil)

    case parent_id && find_in_tree(socket.assigns.categories, parent_id) do
      {:group, {group, children}} ->
        put_on_top(
          socket,
          {group, [{topic, []} | children]},
          [id(topic)],
          post_id,
          id(topic)
        )

      _ ->
        case parent_id && Bonfire.Classify.load_sidebar_category(parent_id) do
          %{type: :group} = group ->
            socket
            |> put_on_top({group, [{topic, []}]}, [id(topic)], post_id, id(topic))
            |> mark_unpinned(id(group))
            |> refresh_dimensions()

          _ ->
            socket
        end
    end
  end

  defp add_loaded(socket, _, _post_id), do: socket

  # the group goes to the top unless this post already moved it (its own message, or its topic's, came first), then it keeps its place; either way the row and the dots are updated, and the post is noted as seen for this row and the group
  defp put_on_top(socket, {group, _} = entry, dotted_ids, post_id, subject_id) do
    seen = socket.assigns.seen_post_ids
    moved? = MapSet.member?(seen, {id(group), post_id})

    categories =
      if moved? do
        Enum.map(socket.assigns.categories, fn {other, _} = row ->
          if id(other) == id(group), do: entry, else: row
        end)
      else
        others =
          Enum.reject(socket.assigns.categories, fn {other, _} -> id(other) == id(group) end)

        [entry | others]
      end

    assign(socket,
      categories: categories,
      new_activity_ids: MapSet.union(socket.assigns.new_activity_ids, MapSet.new(dotted_ids)),
      seen_post_ids: seen |> MapSet.put({id(group), post_id}) |> MapSet.put({subject_id, post_id})
    )
  end

  defp mark_unpinned(socket, group_id),
    do: assign(socket, :unpinned_ids, MapSet.put(socket.assigns.unpinned_ids, group_id))

  # a row added while open has no icon, join mode or membership yet: the same lookups as the load, again for the list
  defp refresh_dimensions(socket), do: socket |> assign_group_dimensions() |> assign_memberships()

  # opening a group or topic clears its dot, for this session
  defp clear_opened(%{assigns: %{new_activity_ids: %MapSet{map: map}}} = socket)
       when map_size(map) == 0,
       do: socket

  defp clear_opened(socket) do
    path = socket.assigns[:current_path]

    opened =
      for {group, children} <- e(socket.assigns, :categories, []),
          {row, row_path} <-
            [{group, path(group)}] ++
              Enum.map(children, fn {topic, _} ->
                {topic, Bonfire.Classify.Web.GroupNavigation.topic_path(group, topic)}
              end),
          MapSet.member?(socket.assigns.new_activity_ids, id(row)),
          active_link?(path, row_path),
          do: id(row)

    assign(
      socket,
      :new_activity_ids,
      MapSet.difference(socket.assigns.new_activity_ids, MapSet.new(opened))
    )
  end

  # register this component's nav-generated id under the user id, so `Pins.LiveHandler.handle_info/2` can reach it via send_updates from within this same (PersistentLive) process (idempotent)
  defp register_for_pin_updates(socket) do
    with user_id when is_binary(user_id) <- current_user_id(socket),
         id when not is_nil(id) <- e(socket.assigns, :id, nil) do
      Bonfire.UI.Common.ComponentID.register_alias(__MODULE__, user_id, id)
    end

    socket
  end

  # the groups pinned to everyone's sidebar, and the user's own, however they change (another tab, an API client); only on the first load, as later updates would subscribe again
  defp subscribe_to_pins(socket) do
    if user_id = current_user_id(socket),
      do: PubSub.subscribe(Bonfire.Social.Pins.group_pins_topics(user_id), socket)

    socket
  end

  defp pinned_tree(user), do: Bonfire.Classify.my_pinned_tree(user) || []
end
