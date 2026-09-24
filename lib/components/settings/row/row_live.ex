defmodule Bonfire.UI.Groups.Settings.RowLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop id, :string, required: true
  prop to, :string, required: true
  prop title, :string, required: true
  prop description, :string, default: nil
  prop value, :string, default: nil
  prop icon, :string, required: true
  prop danger, :boolean, default: false
end
