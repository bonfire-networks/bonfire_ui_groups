defmodule Bonfire.UI.Groups.NewGroupLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop parent, :any, default: nil
  prop parent_id, :any, default: nil
  prop open_btn_class, :css_class, default: "flex items-center gap-2 text-sm text-base-content/80"
end
