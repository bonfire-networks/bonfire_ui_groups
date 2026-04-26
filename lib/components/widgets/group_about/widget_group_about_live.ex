defmodule Bonfire.UI.Groups.WidgetGroupAboutLive do
  @moduledoc """
  Sidebar widget for group pages. Shows the group's governance: audience preset, the three
  permission dimensions (who can join, see, post), parent group, and moderators. Identity +
  primary actions (name, summary, join/follow, stats) live in the hero.
  """
  use Bonfire.UI.Common.Web, :stateless_component

  alias Bonfire.Boundaries.Presets

  prop category, :map, default: nil
  prop parent, :string, default: nil
  prop parent_link, :string, default: nil

  prop preset_slug, :string, default: nil
  prop membership_slug, :string, default: nil
  prop visibility_slug, :string, default: nil
  prop participation_slug, :string, default: nil

  prop moderators, :any, default: []

  defdelegate preset_meta(slug), to: Presets, as: :group_preset_meta
  defdelegate dimension_meta(dim, slug), to: Presets
end
