defmodule Bonfire.UI.Groups.SidebarGroupLive do
  use Bonfire.UI.Common.Web, :stateless_component

  alias Bonfire.UI.Groups.SidebarGroupsLive

  prop category, :any, required: true
  prop children, :list, default: []
  prop parent_id, :string, required: true

  # resolved by `SidebarGroupsLive` for the whole list at once, since deriving it here would be one query per row
  prop preset_icon, :string, default: nil
  prop current_path, :string, default: ""
  prop group_return_to, :string, default: "/groups"

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
