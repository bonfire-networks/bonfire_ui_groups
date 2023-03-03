defmodule Bonfire.UI.Groups.Web.GroupLive do
  use Bonfire.UI.Common.Web, :surface_live_view
  alias Bonfire.UI.Me.LivePlugs

  def tab(selected_tab) do
    case maybe_to_atom(selected_tab) do
      tab when is_atom(tab) -> tab
      _ -> :timeline
    end
    |> debug(selected_tab)
  end

  def mount(params, session, socket) do
    live_plug(params, session, socket, [
      LivePlugs.LoadCurrentAccount,
      LivePlugs.LoadCurrentUser,
      # LivePlugs.LoadCurrentUserCircles,
      # LivePlugs.LoadCurrentAccountUsers,
      Bonfire.UI.Common.LivePlugs.StaticChanged,
      Bonfire.UI.Common.LivePlugs.Csrf,
      Bonfire.UI.Common.LivePlugs.Locale,
      &mounted/3
    ])
  end

  defp mounted(_params, _session, socket) do
    {:ok,
     assign(
       socket,
       group: %{},
       page: "group",
       selected_tab: "timeline",
       nav_items: Bonfire.Common.ExtensionModule.default_nav(:bonfire_ui_social),
       sidebar_widgets: [
        users: [
         secondary: [
           {Bonfire.UI.Topic.WidgetAboutLive, [title: "About " , group: "Welcome", group_link: "/welcome", about: "A sub for ALL parents, step parents, parents-to-be, guardians, caretakers, and anyone else who prefers to base their parenting choices on actual, evidence-backed scientific research.", date: "16 Feb"]},
           {Bonfire.UI.Groups.WidgetMembersLive, [mods: [], members: []]}
         ]
        ],
        guests: [
          secondary: nil
        ]
      ],
       page_title: "group name"
     )}
  end

  def do_handle_params(%{"tab" => tab} = params, _url, socket)
    when tab in ["posts", "boosts", "timeline"] do
  debug(tab, "load tab")

  Bonfire.Social.Feeds.LiveHandler.user_feed_assign_or_load_async(
    tab,
    nil,
    params,
    socket
  )
  end

  def do_handle_params(%{"tab" => tab} = params, _url, socket)
    when tab in ["followers", "followed", "requests", "requested"] do
  debug(tab, "load tab")

  {:noreply,
  assign(
    socket,
    Bonfire.Social.Feeds.LiveHandler.load_user_feed_assigns(
      tab,
      nil,
      params,
      socket
    )

    # |> debug("ffff")
  )}
  end

  def do_handle_event(
        "custom_event",
        _attrs,
        socket
      ) do
    # handle the event here
    {:noreply, socket}
  end

  def handle_params(params, uri, socket),
    do:
      Bonfire.UI.Common.LiveHandlers.handle_params(
        params,
        uri,
        socket,
        __MODULE__
      )

  def handle_info(info, socket),
    do: Bonfire.UI.Common.LiveHandlers.handle_info(info, socket, __MODULE__)

  def handle_event(
        action,
        attrs,
        socket
      ),
      do:
        Bonfire.UI.Common.LiveHandlers.handle_event(
          action,
          attrs,
          socket,
          __MODULE__,
          &do_handle_event/3
        )
end
