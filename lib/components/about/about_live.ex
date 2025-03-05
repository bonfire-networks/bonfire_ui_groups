defmodule Bonfire.UI.Groups.AboutLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop selected_tab, :any, default: "about"
  prop feed_title, :string
  prop user, :map
  prop feed, :list
  prop feed_filters, :any, default: []
  prop page_info, :any
  prop permalink, :string, default: nil
  prop showing_within, :atom, default: nil
  prop follows_me, :boolean, default: false
  prop loading, :boolean, default: false
  prop hide_filters, :boolean, default: false
  slot header
  slot widget

  prop date, :string, default: nil
  prop parent, :string, default: nil
  prop parent_link, :string, default: nil
  prop boundary_preset, :any, default: nil
  prop member_count, :integer, default: 0

  prop members, :list, default: []
  prop moderators, :list, default: []
end
