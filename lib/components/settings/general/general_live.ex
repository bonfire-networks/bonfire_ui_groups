defmodule Bonfire.UI.Groups.Settings.GeneralLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop category, :any, required: true
  prop permalink, :string, default: ""
  prop group_member_count, :integer, default: nil
  prop moderators, :list, default: []
  prop group_membership_slug, :string, default: nil
  prop group_visibility_slug, :string, default: nil

  @doc "Uses the already-loaded dimensions to summarise access without querying boundaries while rendering."
  def render(assigns) do
    assigns
    |> assign(
      membership_label: e(Bonfire.Boundaries.Presets.dimension_meta(:membership, assigns.group_membership_slug), :label, l("Custom membership")),
      visibility_label: e(Bonfire.Boundaries.Presets.dimension_meta(:visibility, assigns.group_visibility_slug), :label, l("Custom visibility"))
    )
    |> render_sface()
  end
end
