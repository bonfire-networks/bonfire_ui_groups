defmodule Bonfire.UI.Groups.WidgetGroupAboutLive do
  @moduledoc "Unified sidebar widget for group pages combining about info, stats, and members."
  use Bonfire.UI.Common.Web, :stateless_component

  prop category, :map, default: nil
  prop date, :string, default: nil
  prop parent, :string, default: nil
  prop parent_link, :string, default: nil
  prop boundary_preset, :any, default: nil
  prop parent_boundary_preset, :any, default: nil
  prop member_count, :integer, default: 0
  prop topic_count, :integer, default: 0
  prop moderators, :any, default: []
  prop members, :any, default: []
end
