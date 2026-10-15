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
  # members keep the toggle regardless, so they can always unfollow
  prop followable, :boolean, default: false
  prop current_path, :string, default: ""
  prop group_return_to, :string, default: "/groups"

  # shared by the follow toggle and menu trigger so they reveal and align together
  @row_action_class "flex !size-8 items-center justify-center rounded-selector cursor-pointer hover:bg-fill-strong focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary [@media(hover:hover)]:opacity-0 group-hover/row:opacity-100 focus-visible:opacity-100 [@media(pointer:coarse)]:!size-10"

  @doc "Renders one pinned group and its visible topics, opening the current group automatically."
  def render(assigns) do
    group_path = path(assigns.category)

    topics =
      for {%{type: :topic} = topic, _children} <- assigns.children do
        topic_path = group_path <> "/topic/" <> (e(topic, :character, :username, nil) || topic.id)

        %{
          id: topic.id,
          name: Bonfire.Classify.Web.Preview.CategoryLive.name(topic, l("Topic")),
          path: path(topic),
          active?:
            SidebarGroupsLive.active_link?(assigns.current_path, topic_path) or
              SidebarGroupsLive.active_link?(assigns.current_path, path(topic))
        }
      end

    active_topic? = Enum.any?(topics, & &1.active?)

    active? =
      SidebarGroupsLive.active_link?(assigns.current_path, group_path) and not active_topic?

    group_name = Bonfire.Classify.Web.Preview.CategoryLive.name(assigns.category, l("Group"))

    assigns
    |> assign(:group_path, group_path)
    |> assign(:group_name, group_name)
    |> assign(:initial, initial(group_name))
    |> assign(:tile_hue, :erlang.phash2(assigns.category.id, 360))
    |> assign(:topics, topics)
    |> assign(:active?, active?)
    |> assign(:expanded?, active? or active_topic?)
    |> assign(:row_id, "#{assigns.parent_id}-group-#{assigns.category.id}")
    |> assign(:row_action_class, @row_action_class)
    |> assign(:show_follow?, assigns.followable or assigns.my_membership == true)
    |> render_sface()
  end

  @doc """
  The first letter of a group's name, for its sidebar tile.

      iex> Bonfire.UI.Groups.SidebarGroupLive.initial("  fedi pub")
      "F"
      iex> Bonfire.UI.Groups.SidebarGroupLive.initial("")
      "#"
  """
  def initial(name) do
    case name |> to_string() |> String.trim() |> String.first() do
      nil -> "#"
      letter -> String.upcase(letter)
    end
  end
end
