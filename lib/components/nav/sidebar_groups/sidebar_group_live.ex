defmodule Bonfire.UI.Groups.SidebarGroupLive do
  use Bonfire.UI.Common.Web, :stateless_component

  alias Bonfire.UI.Groups.SidebarGroupsLive

  prop category, :any, required: true
  prop children, :list, default: []
  prop parent_id, :string, required: true

  # resolved by `SidebarGroupsLive` for the whole list at once, since deriving it here would be one query per row
  prop preset_icon, :string, default: nil
  prop instance_pinned, :boolean, default: false
  # false, :requested or true
  prop my_membership, :any, default: false
  # see `Bonfire.Classify.Categories.join_mode/1`
  prop join_mode, :string, default: nil
  prop current_path, :string, default: ""
  # the rows are patch links with the plain path, so they need no entry page
  # prop group_return_to, :string, default: "/groups"

  @doc "Renders one pinned group and its visible topics, opening the current group automatically."
  def render(assigns) do
    group_path = path(assigns.category)

    topics =
      for {%{type: :topic} = topic, _children} <- assigns.children do
        topic_path = Bonfire.Classify.Web.GroupNavigation.topic_path(assigns.category, topic)

        %{
          id: topic.id,
          name: Bonfire.Classify.Web.Preview.CategoryLive.name(topic, l("Topic")),
          path: topic_path,
          active?:
            SidebarGroupsLive.active_link?(assigns.current_path, topic_path) or
              SidebarGroupsLive.active_link?(assigns.current_path, path(topic))
        }
      end

    active_topic? = Enum.any?(topics, & &1.active?)

    active? =
      SidebarGroupsLive.active_link?(assigns.current_path, group_path) and not active_topic?

    group_name = Bonfire.Classify.Web.Preview.CategoryLive.name(assigns.category, l("Group"))
    row_id = "#{assigns.parent_id}-group-#{assigns.category.id}"

    # members only, as in the group hero
    show_bell? =
      assigns.my_membership == true and
        module_enabled?(Bonfire.Notify.Web.BellButtonLive, assigns[:__context__])

    assigns
    |> assign(:group_path, group_path)
    |> assign(:group_name, group_name)
    |> assign(:topics, topics)
    |> assign(:active?, active?)
    |> assign(:expanded?, active? or active_topic?)
    |> assign(:row_id, row_id)
    |> assign(:show_bell?, show_bell?)
    |> assign(
      :trigger_opts,
      if(show_bell?,
        do: Bonfire.UI.Common.DropdownLive.load_on_first_open("#{row_id}-menu", "#{row_id}-bell"),
        else: []
      )
    )
    |> render_sface()
  end
end
