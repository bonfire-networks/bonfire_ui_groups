defmodule Bonfire.UI.Groups.BoundaryDimensionLive do
  use Bonfire.UI.Common.Web, :stateless_component

  @doc "Atom key for this dimension, e.g. :membership, :visibility"
  prop dimension, :atom, required: true

  @doc "Label for the dimension shown as a heading"
  prop label, :string, required: true

  @doc "Optional description shown below the label"
  prop description, :string, default: nil

  @doc "Ordered list of slugs controlling display order"
  prop slug_order, :list, default: []

  @doc "Map of slug => %{label, description, disabled, disabled_reason}"
  prop options, :map, default: %{}

  @doc "Currently selected slug"
  prop selected, :string, default: nil

  @doc "HTML form field name for the hidden input"
  prop name, :string, required: true

  @doc "phx-target for click events (component id or selector)"
  prop target, :any, default: nil

  @doc "Optional list of user's circles to show as selectable options"
  prop circles, :list, default: []

  @doc "When true, disabled/coming-soon options are shown grayed out. When false (default), they are hidden."
  prop show_unavailable, :boolean, default: false
end
