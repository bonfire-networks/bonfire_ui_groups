defmodule Bonfire.UI.Groups.GroupFiltersLive do
  use Bonfire.UI.Common.Web, :stateless_component

  @doc "The /groups view showing: `:discover`, `:joined`, `:archived`, `:feed` or `:feed_all`"
  prop view, :atom, default: :discover
  prop selected_tab, :string, default: "discover"
  prop search_term, :string, default: ""
  prop join_filter, :string, default: "all"
  prop origin, :string, default: "all"
  @doc "True while the search index answers the typed term, when the public/private switch takes the joining-policy menu's place"
  prop index_search, :boolean, default: false
  prop search_index, :string, default: "public"

  @doc "Builds the shared group view, search, origin and policy form."
  def render(assigns) do
    form =
      to_form(
        %{
          "tab" => assigns.selected_tab,
          "search_term" => assigns.search_term,
          "join_filter" => assigns.join_filter,
          "origin" => assigns.origin,
          "index" => assigns.search_index
        },
        as: :group_filters
      )

    assigns
    |> assign(:form, form)
    |> render_sface()
  end

  # was `l("All groups")`, a string the sidebar still uses
  @doc "The view tabs: the set of groups each lists or follows. Archived groups have no feed, so the feed views have no Archived tab."
  def views(view \\ :discover) do
    [{"discover", l("All known groups")}, {"joined", l("Joined")}, {"archived", l("Archived")}]
    |> Enum.reject(fn {value, _} -> value == "archived" and feed_view?(view) end)
  end

  @doc "The two links of the Groups | Latest updates switch, each `{label, path, current?}`: the directory view and the feed of the same groups, keeping the origin. Archived has no feed, so no switch."
  def modes(view, origin) do
    case Bonfire.UI.Groups.ExploreLive.paired_view(view) do
      nil ->
        []

      paired ->
        {directory, feed} = if view in [:feed, :feed_all], do: {paired, view}, else: {view, paired}
        query = %{"origin" => origin}

        [
          {l("Groups"), Bonfire.UI.Groups.ExploreLive.view_path(directory, query),
           view == directory},
          {l("Latest updates"), Bonfire.UI.Groups.ExploreLive.view_path(feed, query), view == feed}
        ]
    end
  end

  def origins,
    do: [
      {"all", l("All instances")},
      {"local", l("This instance")},
      {"remote", l("Other instances")}
    ]

  def join_policies,
    do: [
      {"all", l("Any joining policy")},
      {"open", l("Open to join")},
      {"request", l("By request")},
      {"invite", l("Invite only")}
    ]

  @doc "The search indexes a search on /groups can read, as the search page's switch names them."
  def search_indexes,
    do: [
      {"public", l("Public only")},
      {"closed", l("Private only")}
    ]

  @doc "True on the feed views, whose posts the search box and the joining policy don't choose."
  def feed_view?(view), do: view in [:feed, :feed_all]

  @doc "The filter menus beside the search box: the origin, then the joining policy, or while the index answers a typed term, the public/private switch in its place. The feed views get the origin alone, as the others choose groups, not posts."
  def menus(assigns) do
    origin =
      {:origin, "group-origin-filters", "ph:globe-hemisphere-west", origins(), assigns.origin,
       "all", l("Filter by where groups are hosted")}

    cond do
      feed_view?(assigns.view) ->
        [origin]

      assigns.index_search ->
        [
          origin,
          {:index, "group-index-filters", "ph:lock-simple-duotone", search_indexes(),
           assigns.search_index, "public", l("Search public or private groups")}
        ]

      true ->
        [
          origin,
          {:join_filter, "group-policy-filters", "ph:door-open", join_policies(),
           assigns.join_filter, "all", l("Filter by joining policy")}
        ]
    end
  end

  @doc "The label of the selected option, which the filter's button shows."
  def selected_label(options, value),
    do: Enum.find_value(options, elem(hd(options), 1), fn {v, label} -> v == value && label end)
end
