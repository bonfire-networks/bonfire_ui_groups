defmodule Bonfire.UI.Groups.Settings.BoundariesLive do
  @moduledoc """
  Group settings tab for editing the group's boundaries via the same three-layer
  permission UX as the new-group modal (preset → fine-tune → advanced dimensions).
  The current preset (or `"custom"` if the group has been customised away from any
  preset) is preselected so the admin can see what they're changing from.
  """

  use Bonfire.UI.Common.Web, :stateful_component

  prop selected_tab, :any, default: nil
  prop category, :any, required: true
  prop boundary_preset, :any, default: nil

  data initial_preset, :string, default: nil
  data initial_membership, :string, default: nil
  data initial_visibility, :string, default: nil
  data initial_participation, :string, default: nil
  data initial_default_content_visibility, :string, default: nil

  # Preset detection walks ACLs and reads settings. Run only on first mount;
  # parent re-renders must not re-query (would also clobber the inner editor).
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    socket =
      if Map.has_key?(socket.assigns, :initial_preset) and
           not is_nil(socket.assigns.initial_preset) do
        socket
      else
        state = detect_preset_state(socket.assigns.category)

        assign(socket,
          initial_preset: state.preset,
          initial_membership: state.membership,
          initial_visibility: state.visibility,
          initial_participation: state.participation,
          initial_default_content_visibility: state.default_content_visibility
        )
      end

    {:ok, socket}
  end

  defp detect_preset_state(category) do
    dim_slugs = Bonfire.Boundaries.Presets.group_dimension_slugs(category)
    preset = Bonfire.Boundaries.Presets.preset_slug_from_dims(dim_slugs) || "custom"

    # Fill any dim left nil by detection (e.g. circle-controlled participation
    # like `group_members`) from the resolved preset's declared dims, so the
    # editor's hidden inputs round-trip on an unchanged re-submit.
    meta = Bonfire.Boundaries.Presets.group_preset_meta(preset) || %{}

    %{
      preset: preset,
      membership: dim_slugs[:membership] || e(meta, :membership, nil),
      visibility: dim_slugs[:visibility] || e(meta, :visibility, nil),
      participation: dim_slugs[:participation] || e(meta, :participation, nil),
      default_content_visibility:
        Bonfire.Classify.Boundaries.read_default_content_visibility(category)
    }
  end
end
