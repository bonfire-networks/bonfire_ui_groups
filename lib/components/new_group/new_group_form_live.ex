defmodule Bonfire.UI.Groups.NewGroupFormLive do
  @moduledoc """
  Interactive form for creating a new group. The three-layer permission UX
  (preset → fine-tune → advanced dimensions) is provided by the embedded
  `Bonfire.UI.Groups.GroupBoundaryEditorLive`; this component only owns the
  surrounding form (name, description, submit, parent context).

  Rendered as a stateful child of `OpenModalLive` so that state updates
  re-render inside the reusable modal — an outer component holding this state
  would be frozen at modal-open time.
  """

  use Bonfire.UI.Common.Web, :stateful_component

  prop parent, :any, default: nil
  prop parent_id, :any, default: nil

  @doc "When true, locked/unavailable Layer 2 toggles are shown as disabled. When false (default), they are hidden."
  prop show_unavailable_toggles, :boolean, default: false
end
