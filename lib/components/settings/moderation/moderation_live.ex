defmodule Bonfire.UI.Groups.Settings.ModerationLive do
  @moduledoc "A group's moderation page: its moderation inbox (reports, join requests, submissions) and log (moderation records)."
  use Bonfire.UI.Common.Web, :stateless_component

  prop selected_tab, :any, default: nil
  prop category, :any, required: true
end
