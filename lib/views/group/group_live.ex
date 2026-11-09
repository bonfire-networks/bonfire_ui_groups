defmodule Bonfire.UI.Groups.GroupLive do
  use Bonfire.UI.Common.Web, :surface_live_view

  on_mount {LivePlugs, [Bonfire.UI.Me.LivePlugs.LoadCurrentUser]}

  def mount(%{"id" => id} = params, session, socket) when id != "" do
    with {:ok, socket} <-
           undead_mount(socket, fn ->
             Bonfire.Classify.LiveHandler.mounted(params, session, socket)
           end) do
      case e(assigns(socket), :category, nil) do
        # `mounted/3` found nothing this visitor may see (a members-private group seen by a guest, say), and `undead_mount/2` still answers `{:ok, socket}`, having already sent them to the not-found page. There is no group to build the rest from
        nil ->
          {:ok, socket}

        category ->
          # emit social-card metadata (name/description/image) for the group/topic profile,
          # via the Category `SEO.*.Build` impls in group_seo.ex (no-op on non-guest/connected renders)
          {:ok, Bonfire.UI.Common.SEO.maybe_assign_seo(socket, category)}
      end
    end
  end

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> redirect_to("/groups")}
  end

  def handle_params(params, uri, socket) do
    leaving_settings? =
      e(socket.assigns, :selected_tab, nil) == "settings" and params["tab"] != "settings"

    previous_id = id(e(assigns(socket), :category, nil))

    # the topic chips and the sidebar's rows patch between groups and their topics, all served by this view
    case Bonfire.Classify.LiveHandler.maybe_switch_category(params, socket) do
      {:ok, socket} ->
        socket
        |> reset_members_filters_on_switch(previous_id)
        |> assign_page()
        |> handle_category_params(params, uri, leaving_settings?)

      # a stale link or Back to a topic since removed: stay on what was showing, at its own URL
      {:error, _} ->
        {:noreply,
         socket
         |> assign_flash(:error, l("That topic isn't available."))
         |> push_patch(to: canonical_path(socket), replace: true)}
    end
  end

  # the members page's search and role filter are the view's own state (`Bonfire.UI.Groups.LiveHandler`), which `Bonfire.Classify.LiveHandler.load_category/4` knows nothing of: a patch to another group or topic starts them afresh
  defp reset_members_filters_on_switch(socket, previous_id) do
    if not is_nil(previous_id) and previous_id != id(e(assigns(socket), :category, nil)),
      do: assign(socket, member_search: "", member_role: "all"),
      else: socket
  end

  # `_leaving_settings?`: back no longer depends on it (see the commented `back:` below)
  defp handle_category_params(socket, params, uri, _leaving_settings?) do
    {:noreply, socket} = Bonfire.Classify.LiveHandler.handle_params(params, uri, socket)

    socket =
      socket
      |> assign(:tab_id, params["tab_id"])
      |> assign(:composer_opts, composer_opts(socket.assigns.category))
      |> assign(:no_header, socket.assigns.selected_tab == "members")
      |> assign_new(:member_search, fn -> "" end)
      |> assign_new(:member_role, fn -> "all" end)

    # members get a compact hero, with its avatar and toggle in the page header
    shown? = hero_shown?(socket.assigns)

    socket =
      socket
      |> assign(:hero_shown?, shown?)
      |> Bonfire.UI.Groups.GroupHeroLive.assign_page_header(
        if(shown?, do: socket.assigns.frame_group),
        e(socket.assigns, :my_group_membership, false)
      )

    socket =
      if socket.assigns.selected_tab == "settings" do
        socket
        |> assign(:page_title, Bonfire.UI.Groups.SettingsLive.page_title(socket.assigns.tab_id))
        # the settings' back is the group (or its settings), served by this view, so a patch with the plain path: the view keeps the entry page
        # |> assign(
        #   :back,
        #   Bonfire.Classify.Web.GroupNavigation.link(
        #     if(socket.assigns.tab_id,
        #       do: path(socket.assigns.category) <> "/settings",
        #       else: path(socket.assigns.category)
        #     ),
        #     socket.assigns.group_return_to
        #   )
        # )
        |> assign(
          back:
            if(socket.assigns.tab_id,
              do: path(socket.assigns.category) <> "/settings",
              else: path(socket.assigns.category)
            ),
          back_patch: true
        )
      else
        assign(socket,
          page_title: Bonfire.Classify.Web.Preview.CategoryLive.name(socket.assigns.category),
          # back is the entry page on every tab but members, whose back is the group (set by its clause, on each patch to it): a patch from members to the group keeps the entry page, as the view's state holds it
          # back:
          #   if(leaving_settings? and socket.assigns.selected_tab != "members",
          #     do: socket.assigns.group_return_to,
          #     else: socket.assigns.back
          #   )
          back:
            if(socket.assigns.selected_tab != "members",
              do: socket.assigns.group_return_to,
              else: socket.assigns.back
            ),
          # the entry page is another view's page, so a navigate; the members page's back (the group) is a patch
          back_patch: socket.assigns.selected_tab == "members"
        )
      end

    {:noreply,
     socket
     |> maybe_patch_to_canonical_topic_url(uri)
     |> maybe_patch_remote_settings_to_moderation()}
  end

  defp canonical_path(socket) do
    if in_group_topic?(socket),
      do:
        Bonfire.Classify.Web.GroupNavigation.topic_path(
          socket.assigns.frame_group,
          socket.assigns.category
        ),
      else: path(socket.assigns.category)
  end

  defp in_group_topic?(socket),
    do:
      e(assigns(socket), :type, nil) == :topic and
        not is_nil(e(assigns(socket), :frame_group, nil))

  @doc """
  Whether the page is a group's settings, where the header and the composer step aside. A topic's settings open in a modal from its bar instead.

      iex> Bonfire.UI.Groups.GroupLive.group_settings?(:group, "settings")
      true
      iex> Bonfire.UI.Groups.GroupLive.group_settings?(:topic, "settings")
      false
      iex> Bonfire.UI.Groups.GroupLive.group_settings?(:group, "discussions")
      false
  """
  def group_settings?(type, selected_tab), do: type != :topic and selected_tab == "settings"

  @doc """
  Whether the feed starts with the "Discussions" / "Latest updates" tabs (`Bonfire.UI.Social.DiscussionsViewOptionsLive`, shown on the `:recent_discussions` feed to someone signed in), which draw their own rule, so the header's and the pins' bottom borders above them would double it. Not when the access gate or sensitive notice stands in for the feed.

      iex> Bonfire.UI.Groups.GroupLive.discussions_tabs?(%{selected_tab: :discussions, view_mode: :full}, "user_id")
      true
      iex> Bonfire.UI.Groups.GroupLive.discussions_tabs?(%{selected_tab: "posts", view_mode: :full}, "user_id")
      false
      iex> Bonfire.UI.Groups.GroupLive.discussions_tabs?(%{selected_tab: "discussions", view_mode: :full}, nil)
      false
  """
  def discussions_tabs?(assigns, current_user_id) do
    to_string(e(assigns, :selected_tab, nil)) == "discussions" and not is_nil(current_user_id) and
      e(assigns, :view_mode, :full) == :full and not e(assigns, :sensitive_notice?, false)
  end

  defp assign_page(socket) do
    if e(assigns(socket), :type, nil) == :topic,
      do: assign(socket, page: "topic", showing_within: :topic),
      else: assign(socket, page: "group", showing_within: :group)
  end

  # A group hosted on another instance is managed there, so its settings here open on Moderation, the one page that works across instances: its reports, and the removals, locks and bans its moderators here send to the group. `replace: true` for the same back-button reason as below
  defp maybe_patch_remote_settings_to_moderation(socket) do
    category = e(assigns(socket), :category, nil)

    if e(assigns(socket), :selected_tab, nil) == "settings" and
         e(assigns(socket), :tab_id, nil) != "moderation" and not is_nil(category) and
         not Bonfire.Social.is_local?(category),
       do: push_patch(socket, to: path(category) <> "/settings/moderation", replace: true),
       else: socket
  end

  # A topic reached by another URL (eg. the feed's `/&<topic_id>` link) is patched in place to its canonical one. `replace: true`, or Back would land on the old URL and patch forward again.
  defp maybe_patch_to_canonical_topic_url(socket, uri) do
    if in_group_topic?(socket) do
      canonical = canonical_path(socket)

      if URI.parse(uri).path != canonical,
        do:
          push_patch(socket,
            to: URI.to_string(%URI{path: canonical, query: URI.parse(uri).query}),
            replace: true
          ),
        else: socket
    else
      socket
    end
  end

  @doc "The inline composer's options, built once per category by `handle_category_params/4`, as `read_default_content_visibility/1` is a query. The post's audience and ACLs come from the group it is published in (`Bonfire.Classify.Boundaries.post_boundary_options/3`); `to_circles` is for feed targeting."
  def composer_opts(category) do
    %{
      context_id: id(category),
      mentions: [id(category)],
      to_circles: Bonfire.Classify.Boundaries.post_circles_for_group(category),
      to_boundaries:
        List.wrap(Bonfire.Classify.Boundaries.read_default_content_visibility(category))
    }
    # in a group or topic marked sensitive, the composer opens with "sensitive" on, which the author can turn off: a prefill, nothing is enforced at publish
    |> Map.merge(
      if(Bonfire.Classify.Categories.sensitive?(category), do: %{show_sensitive: true}, else: %{})
    )
  end

  @doc """
  The tab's body component, before gates.
  """
  def section_component(type, selected_tab, tab_id) do
    if type == :topic,
      do:
        Config.get([:ui, :topic, :sections], [])[tab(selected_tab)] ||
          Bonfire.UI.Social.ProfileTimelineLive,
      else:
        tab_component(selected_tab) || tab_component(tab_id) ||
          Bonfire.UI.Social.ProfileTimelineLive
  end

  # the hero lives in the body component's `header` slot: tabs without one (eg. the topic directory) and group settings show none
  defp hero_shown?(assigns) do
    type = e(assigns, :type, nil)
    selected_tab = e(assigns, :selected_tab, nil)
    module = section_component(type, selected_tab, e(assigns, :tab_id, nil))

    not is_nil(e(assigns, :frame_group, nil)) and not group_settings?(type, selected_tab) and
      Code.ensure_loaded?(module) and function_exported?(module, :__slots__, 0) and
      Enum.any?(module.__slots__(), &(&1.name == :header))
  end

  def tab(selected_tab) do
    case maybe_to_atom(selected_tab) do
      tab when is_atom(tab) -> tab
      _ -> :timeline
    end
    |> debug(selected_tab)
  end

  def tab_component(selected_tab) do
    default = nil
    tab_section = Config.get([:ui, :group, :sections], [])[tab(selected_tab)]

    if not is_nil(tab_section) and is_atom(tab_section) and module_enabled?(tab_section) do
      debug(tab_section, "ok")
      tab_section
    else
      debug("default")
      default
    end
  end
end
