defmodule Bonfire.UI.Groups.WidgetGroupLive do
  @moduledoc """
  The group's reference card in the right rail (the drawer on a phone): About (access details, creation date, parent group), Rules, Moderators and On the fediverse. Everything it shows is loaded by the page, so it runs no queries.
  """
  use Bonfire.UI.Common.Web, :stateless_component

  prop group, :any, required: true

  @doc "The group this one is part of, for nested groups."
  prop parent, :any, default: nil

  prop moderators, :list, default: []

  @doc "Display-ready rules sections, see `Bonfire.CommunityRules.get_entity_rules_sections/1`. Never `nil`: `any_rules?(nil)` reads the instance's rules instead."
  prop rules_sections, :list, default: []

  prop membership_slug, :string, default: nil
  prop visibility_slug, :string, default: nil
  prop participation_slug, :string, default: nil
  prop content_visibility_slug, :string, default: nil

  @doc "When the group was created, already formatted."
  prop created, :string, default: nil

  @doc "The page's tab: the members tab lists the moderators itself."
  prop selected_tab, :any, default: nil

  def render(assigns) do
    assigns
    |> assign(
      :access_rows,
      access_rows(
        assigns.membership_slug,
        assigns.visibility_slug,
        assigns.participation_slug,
        assigns.content_visibility_slug
      )
    )
    |> render_sface()
  end

  @doc """
  The access dimensions, in reading order, for both the About rows and "How access works": each with its slug, an icon, the row's short label, the details' longer one (the rows sit beside their values, the details stand alone) and the preset's metadata. A dimension whose slug has no preset is left out.

      iex> Bonfire.UI.Groups.WidgetGroupLive.access_rows("open", "global", "group_members", "public") |> Enum.map(&elem(&1, 0))
      [:membership, :visibility, :participation, :default_content_visibility]
      iex> Bonfire.UI.Groups.WidgetGroupLive.access_rows("open", nil, nil, nil) |> Enum.map(&elem(&1, 0))
      [:membership]
  """
  def access_rows(membership_slug, visibility_slug, participation_slug, content_visibility_slug) do
    [
      {:membership, membership_slug, "ph:door-open", l("Joining"), l("Joining")},
      {:visibility, visibility_slug, "ph:eye", l("Visible"), l("Visibility")},
      {:participation, participation_slug, "ph:pencil-simple-line", l("Posting"), l("Posting")},
      {:default_content_visibility, content_visibility_slug, "ph:lock-simple", l("New posts"),
       l("Default post visibility")}
    ]
    |> Enum.flat_map(fn {dimension, slug, icon, label, details} ->
      case Bonfire.Boundaries.Presets.dimension_meta(dimension, slug) do
        %{} = meta -> [{dimension, slug, icon, label, details, meta}]
        _ -> []
      end
    end)
  end

  @doc """
  Who a dimension's preset admits, for "How access works". Two presets name their audience by what they check rather than who it is, so they read as "Anyone on this instance".

      iex> Bonfire.UI.Groups.WidgetGroupLive.audience_label(:membership, "local:members", %{label: "Local users"})
      "Anyone on this instance"
      iex> Bonfire.UI.Groups.WidgetGroupLive.audience_label(:visibility, "global", %{label: "Everyone"})
      "Everyone"
  """
  def audience_label(:membership, "local:members", _meta), do: l("Anyone on this instance")

  def audience_label(:participation, "local:contributors", _meta),
    do: l("Anyone on this instance")

  def audience_label(_dimension, _slug, meta), do: e(meta, :label, nil)
end
