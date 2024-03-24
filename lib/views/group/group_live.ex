defmodule Bonfire.UI.Groups.GroupLive do
  use Bonfire.UI.Common.Web, :surface_live_view

  declare_extension("Groups",
    icon: "emojione:circus-tent",
    emoji: "🎪",
    description:
      l("Organise in groups, whether public or private, open or close, or anything in between."),
    default_nav: [
      Bonfire.UI.Groups.SidebarGroupsLive
    ]
  )

  on_mount {LivePlugs, [Bonfire.UI.Me.LivePlugs.LoadCurrentUser]}

  def mount(%{"id" => id} = params, session, socket) when id != "" do
    debug(params, "ppppp")

    with {:ok, socket} <-
           undead_mount(socket, fn ->
             Bonfire.Classify.LiveHandler.mounted(params, session, socket)
           end) do
      {:ok,
       assign(
         socket,
         page: "group",
         nav_items: Bonfire.Common.ExtensionModule.default_nav(),
         showing_within: :group
         #  smart_input_opts: [hide_buttons: true]
       )}
    end
  end

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> redirect_to("/groups")}
  end

  def handle_params(params, uri, socket),
    do:
      Bonfire.Classify.LiveHandler.handle_params(
        params,
        uri,
        socket
      )

  def tab(selected_tab) do
    case maybe_to_atom(selected_tab) do
      tab when is_atom(tab) -> tab
      _ -> :timeline
    end
    |> debug(selected_tab)
  end

  def tab_component(selected_tab) do
    default = nil
    tab_section = Config.get([:ui, :group, :sections, tab(selected_tab)])

    if not is_nil(tab_section) and is_atom(tab_section) and module_enabled?(tab_section) do
      debug(tab_section, "ok")
      tab_section
    else
      debug("default")
      default
    end
  end
end
