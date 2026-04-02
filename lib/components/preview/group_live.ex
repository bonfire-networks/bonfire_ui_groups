defmodule Bonfire.UI.Groups.Preview.GroupLive do
  use Bonfire.UI.Common.Web, :stateless_component
  alias Bonfire.Classify.Categories

  prop object, :any
  prop activity, :any, default: nil
  prop object_boundary, :any, default: nil
  prop permalink, :string, default: nil
  prop showing_within, :atom, default: nil

  def preloads(),
    do: [
      :character,
      :profile,
      parent_category: [:profile, :character]
    ]

  def name(object) do
    Bonfire.Classify.Web.Preview.CategoryLive.name(object, l("Unnamed group"))
  end

  # TODO: preload?
  # defp crumbs(%{name: name, parent: grandparent} = _parent) do
  #   crumbs(grandparent) <> crumb_link(name)
  # end

  # defp crumbs(%{name: name}) do
  #   crumb_link(name)
  # end

  # defp crumbs(_) do
  #   ""
  # end

  def crumb_link(name) do
    "<a data-phx-link='redirect' data-phx-link-state='push' href='/+#{name}'>#{name}</a> > "
  end
end
