defmodule Bonfire.UI.Groups.ExploreLive do
  use Bonfire.UI.Common.Web, :surface_live_view
  alias Bonfire.Classify.Categories
  alias Bonfire.Classify

  declare_extension("Groups",
    icon: "ph:users-three-bold",
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
    icon: "ph:users-three-bold",
    icon_active: "ph:users-three-fill"
  )

  def mount(params, session, socket) do
    with %{edges: list, page_info: page_info} <-
           Categories.list_tree([:default, type: :group, tree_max_depth: 1],
             current_user: current_user(socket)
           )
           |> debug("grrrr") do
      {:ok,
       assign(socket,
         page: "groups",
         page_title: "Groups",
         categories: list,
         page_info: page_info,
         nav_items: Bonfire.Common.ExtensionModule.default_nav(),
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
