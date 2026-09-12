defmodule Bonfire.UI.Groups.Preview.GroupLive do
  use Bonfire.UI.Common.Web, :stateless_component
  alias Bonfire.Classify.Categories

  prop object, :any
  prop preview, :map, default: %{}
  prop activity, :any, default: nil
  prop object_boundary, :any, default: nil
  prop permalink, :string, default: nil
  prop showing_within, :atom, default: nil

  def preloads(),
    do: [
      :character,
      :profile,
      parent_category: [:profile, :character]
    ]

  def name(object) do
    Bonfire.Classify.Web.Preview.CategoryLive.name(object, l("Unnamed group"))
  end

  # TODO (perf): row_chip walks the group's ACLs on every render.
  # Batch-preload via `update_many/1` or resolve once in ExploreLive.mount.
  defdelegate row_chip(group), to: Bonfire.Boundaries.Presets, as: :group_row_chip

  @doc "Returns the federated handle displayed on a group card."
  def handle(object) do
    Bonfire.Me.Characters.display_username(object, true) ||
      e(object, :character, :username, nil)
  end

  @doc "Labels group scope using the preloaded listing dimensions."
  def scope_meta(object, preview) do
    if Bonfire.Me.Integration.is_local?(object) do
      scope =
        case e(preview, :visibility, nil) do
          slug when is_binary(slug) -> slug |> String.split(":", parts: 2) |> List.first()
          _ -> nil
        end

      Bonfire.Boundaries.Presets.scopes()
      |> Enum.find_value(%{label: l("Group"), icon: "ph:users-three-duotone"}, fn {key, meta} ->
        if to_string(key) == scope, do: meta
      end)
    else
      %{label: l("Remote group"), icon: "ph:globe-hemisphere-west-duotone"}
    end
  end

  @doc "Returns a topic label for the group card."
  def topic_name(topic),
    do: e(topic, :profile, :name, nil) || e(topic, :name, nil)

  @doc "Labels remote counts explicitly as members on this instance."
  def member_label(count, remote?) when is_integer(count) do
    if remote? do
      lp("%{count} member here", "%{count} members here", count, count: count)
    else
      lp("%{count} member", "%{count} members", count, count: count)
    end
  end

  @doc "Whether the group is hosted on another instance."
  def remote?(object), do: !Bonfire.Me.Integration.is_local?(object)

end
