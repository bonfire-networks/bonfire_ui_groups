defmodule Bonfire.UI.Groups.Settings.MembershipLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop selected_tab, :any, default: nil
  prop category, :any, required: true

  prop user, :map
  prop feed, :list, default: []
  prop page_info, :any, default: nil
  prop showing_within, :atom, default: :profile
  prop hide_tabs, :boolean, default: false
end
