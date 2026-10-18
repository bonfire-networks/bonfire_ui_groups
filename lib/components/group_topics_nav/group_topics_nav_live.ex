defmodule Bonfire.UI.Groups.GroupTopicsNavLive do
  @moduledoc """
  A group's topics as a row of chips under its header: "All", then one per topic. Each chip live patches to the topic's in-group URL, which `Bonfire.UI.Groups.GroupLive` renders in the same frame, so the chips act as a filter on the group. "New topic" sits outside the scroll, for whoever may create one.
  """
  use Bonfire.UI.Common.Web, :stateless_component

  prop group, :any, required: true
  prop topics, :list, default: []
  prop group_return_to, :string, default: "/groups"

  @doc "The topic being shown, whose chip is current; `nil` on the group page, where All is."
  prop selected_topic_id, :string, default: nil

  @doc "Whether to offer New topic, see `Bonfire.Classify.can_create_topic?/2`. Decided by the page, once."
  prop can_create_topic, :boolean, default: false

  @doc """
  Whether to show the row: when there are topics, or when the viewer may create the first one.

      iex> Bonfire.UI.Groups.GroupTopicsNavLive.show?([], false)
      false
      iex> Bonfire.UI.Groups.GroupTopicsNavLive.show?([], true)
      true
  """
  def show?(topics, can_create_topic), do: (is_list(topics) and topics != []) or can_create_topic

  def topics_label(group),
    do: l("Topics in %{name}", name: e(group, :profile, :name, l("this group")))

  # the `::before` stretches the 32px pill's touch target to 44px without making it look chunky
  @chip_base "relative flex h-8 items-center gap-1 whitespace-nowrap rounded-full px-3.5 text-sm font-medium transition-colors before:absolute before:inset-x-0 before:-inset-y-1.5 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary "

  @doc "A chip's classes; `current` for the chip of the page being shown."
  def chip_class(current) do
    @chip_base <>
      if(current,
        do: "bg-base-content text-base-100",
        else: "bg-fill text-base-content hover:bg-fill-strong"
      )
  end

  @doc """
  The New topic button's classes: a chip in the primary colour.

      iex> Bonfire.UI.Groups.GroupTopicsNavLive.new_topic_class() =~ "focus-visible:outline-primary"
      true
  """
  def new_topic_class, do: @chip_base <> "bg-primary text-primary-content hover:bg-primary/90"
end
