defmodule Bonfire.UI.Groups.Settings.DetailLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop category, :any, required: true
  prop tab_id, :string, required: true
end
