defmodule Bonfire.UI.Groups.Settings.GeneralLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop category, :any, required: true
  prop permalink, :string, default: ""
  prop group_member_count, :integer, default: nil
  prop moderators, :list, default: []
  prop group_membership_slug, :string, default: nil
  prop group_visibility_slug, :string, default: nil

  @doc "The overview's rows come from the settings `navigation` config (`Bonfire.UI.Groups.RuntimeConfig`), section by section."
  def render(assigns) do
    assigns
    |> assign(
      people_entries: entries(:people, assigns),
      management_entries: entries(:management, assigns),
      admin_entries: entries(:admin, assigns),
      danger_entries: entries(:danger, assigns)
    )
    |> render_sface()
  end

  @doc "The configured entries for one section of the overview, keeping only those the viewer may see, with their computed `description`/`value` resolved."
  def entries(group, assigns) do
    Config.get([:ui, :group, :settings, :navigation], [])
    |> Enum.filter(fn {_key, entry} ->
      is_map(entry) and entry[:group] == group and shown?(entry, assigns)
    end)
    |> Enum.map(fn {key, entry} ->
      entry
      |> Map.put(:to, assigns[:permalink] <> "/settings/#{key}")
      |> Map.update(:description, nil, &resolve(&1, assigns))
      |> Map.update(:value, nil, &resolve(&1, assigns))
    end)
  end

  defp shown?(entry, assigns) do
    (is_nil(entry[:module]) or module_enabled?(entry[:module], assigns[:__context__])) and
      case entry[:can] do
        nil -> true
        {verb, :group} -> Bonfire.Boundaries.can?(assigns[:__context__], verb, assigns[:category])
        {verb, object} -> Bonfire.Boundaries.can?(assigns[:__context__], verb, object)
      end
  end

  defp resolve(fun, assigns) when is_function(fun, 1), do: fun.(assigns)
  defp resolve(other, _assigns), do: other

  @doc "Uses the already-loaded dimensions to summarise access without querying boundaries while rendering."
  def membership_label(assigns),
    do:
      e(
        Bonfire.Boundaries.Presets.dimension_meta(:membership, assigns[:group_membership_slug]),
        :label,
        l("Custom membership")
      )

  def visibility_label(assigns),
    do:
      e(
        Bonfire.Boundaries.Presets.dimension_meta(:visibility, assigns[:group_visibility_slug]),
        :label,
        l("Custom visibility")
      )

  def auto_join_label(assigns),
    do:
      if(Bonfire.Classify.Categories.auto_join_new_users?(assigns[:category]),
        do: l("Auto-join on"),
        else: l("Auto-join off")
      )
end
