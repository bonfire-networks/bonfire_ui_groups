defmodule Bonfire.UI.Groups.GroupTopicsNavLive do
  @moduledoc """
  Horizontal navigation between a group and its topics, rendered between the
  persistent group hero and the feed. The "All" tab links to the group itself;
  each subsequent tab links to a topic. Hidden entirely when a group has no
  topics.
  """
  use Bonfire.UI.Common.Web, :stateless_component

  prop group, :any, required: true
  prop topics, :list, default: []
  prop selected_id, :any, default: nil
end
