defmodule Bonfire.UI.Groups.WidgetGroupAboutLive do
  @moduledoc "Group sidebar showing the parent group and moderators. Access details live in the group hero."
  use Bonfire.UI.Common.Web, :stateless_component

  prop parent, :string, default: nil
  prop parent_link, :string, default: nil

  prop moderators, :any, default: []
  prop selected_tab, :any, default: nil
end
