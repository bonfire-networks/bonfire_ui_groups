defmodule Bonfire.UI.Groups.GroupLive do
  use Bonfire.UI.Common.Web, :surface_live_view

  declare_extension("Groups",
    icon: "emojione:circus-tent",
    default_nav: [
      Bonfire.UI.Groups.SidebarGroupsLive
    ]
  )

  on_mount {LivePlugs, [Bonfire.UI.Me.LivePlugs.LoadCurrentUser]}

  def mount(params, session, socket) do
    with {:ok, socket} <- Bonfire.Classify.LiveHandler.mounted(params, session, socket) do
      {:ok,
       assign(
         socket,
         page: "group",
         nav_items: Bonfire.Common.ExtensionModule.default_nav(:bonfire_ui_social),
         showing_within: :group
         #  smart_input_opts: [hide_buttons: true]
       )}
    end
  end

  def handle_params(params, uri, socket),
    do:
      Bonfire.UI.Common.LiveHandlers.handle_params(
        params,
        uri,
        socket,
        __MODULE__,
        &Bonfire.Classify.LiveHandler.do_handle_params/3
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
          __MODULE__
          # &do_handle_event/3
        )

  def tab(selected_tab) do
    case maybe_to_atom(selected_tab) do
      tab when is_atom(tab) -> tab
      _ -> :timeline
    end
    |> debug(selected_tab)
  end
end
