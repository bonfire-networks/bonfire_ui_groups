defmodule Bonfire.UI.Groups.ExploreLive do
  use Bonfire.UI.Common.Web, :surface_live_view
  alias Bonfire.Classify.Categories
  alias Bonfire.Classify

  on_mount {LivePlugs, [Bonfire.UI.Me.LivePlugs.LoadCurrentUser]}

  def mount(params, session, socket) do
    with %{edges: list, page_info: page_info} <-
           Categories.list_tree([:default, type: :group, tree_max_depth: 1],
             current_user: current_user(socket.assigns)
           )
           |> debug("grrrr") do
      {:ok,
       assign(socket,
         page: "groups",
         page_title: "Groups",
         categories: list,
         page_info: page_info,
         nav_items: Bonfire.Common.ExtensionModule.default_nav(:bonfire_ui_social),
         page_header_aside: [
           {Bonfire.UI.Groups.NewGroupLive,
            [
              parent_id: "explore",
              open_btn_class:
                "btn btn-outline btn-sm btn-primary rounded-full !border-primary/30 normal-case"
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
end
