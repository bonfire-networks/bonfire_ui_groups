defmodule Bonfire.UI.Groups.GroupTopicsNavLive do
  @moduledoc """
  A group's topics as a row of chips under its header: "All", then one per topic. Each chip live patches to the topic's in-group URL, which `Bonfire.UI.Groups.GroupLive` renders in the same frame, so the chips act as a filter on the group. The selected topic's chip opens that topic's actions (follow, notifications, settings), which replaces a separate topic header row. "New topic" ends the row, for whoever may create one.
  """
  use Bonfire.UI.Common.Web, :stateless_component

  prop group, :any, required: true
  prop topics, :list, default: []
  prop group_return_to, :string, default: "/groups"

  @doc "The topic being shown, whose chip is current and opens its actions; `nil` on the group page, where All is."
  prop selected_topic, :any, default: nil

  @doc "Whether to offer New topic, see `Bonfire.Classify.can_create_topic?/2`. Decided by the page, once."
  prop can_create_topic, :boolean, default: false

  @doc "Whether to offer Topic settings in the selected chip's menu, see `Bonfire.Classify.ensure_update_allowed/3`. Decided by the page, once."
  prop can_edit_topic, :boolean, default: false

  @doc """
  Whether `topic` is the one being shown.

      iex> Bonfire.UI.Groups.GroupTopicsNavLive.selected?(%{id: "01M5A1RS1M5A1RS1M5A1RS1M5"}, %{id: "01M5A1RS1M5A1RS1M5A1RS1M5"})
      true
      iex> Bonfire.UI.Groups.GroupTopicsNavLive.selected?(%{id: "01M5A1RS1M5A1RS1M5A1RS1M5"}, nil)
      false
  """
  def selected?(_topic, nil), do: false
  def selected?(topic, selected_topic), do: id(topic) == id(selected_topic)

  def topic_name(topic), do: e(topic, :profile, :name, l("Untitled topic"))

  # the menu's bell asks for its state only when the menu first opens, so a topic page runs no notification query up front (as in `Bonfire.UI.Groups.SidebarGroupLive`)
  def menu_trigger_opts(topic_id) do
    [
      "aria-current": "page",
      "data-role": "group-topic-current",
      "phx-click":
        JS.push("load", target: "#group_topic_bell_#{topic_id}")
        |> JS.remove_attribute("phx-click", to: "#group-topic-menu-#{topic_id}_trigger")
    ]
  end

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

  @doc """
  The list's classes: a horizontally scrolling row that fades at whichever edge has more chips, or, with no topics, a padded box for the New topic bar. The row's bottom padding holds the chips' `::before` touch targets, since `overflow-x-auto` makes `overflow-y` auto too and they'd otherwise scroll it vertically.

      iex> Bonfire.UI.Groups.GroupTopicsNavLive.list_class([]) =~ "overflow-x-auto"
      false
  """
  def list_class([]), do: "flex min-w-0 flex-1 list-none gap-1.5 px-4 py-1"

  def list_class(_topics),
    do:
      "flex min-w-0 flex-1 list-none gap-1.5 overflow-x-auto pt-3 pb-1.5 pl-4 [scrollbar-width:none] data-[fade-end]:[mask-image:linear-gradient(to_right,black_calc(100%-3rem),transparent)] data-[fade-start]:[mask-image:linear-gradient(to_right,transparent,black_3rem)] data-[fade-start]:data-[fade-end]:[mask-image:linear-gradient(to_right,transparent,black_3rem,black_calc(100%-3rem),transparent)] [&::-webkit-scrollbar]:hidden"

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
  The New topic button's classes. With no topics yet it's a full-width bar, muted so it stays quieter than the composer right below it; otherwise a ghost chip at the end of the topic chips, so it scrolls with them rather than competing for the row.

      iex> Bonfire.UI.Groups.GroupTopicsNavLive.new_topic_class(true) =~ "justify-center"
      true
      iex> Bonfire.UI.Groups.GroupTopicsNavLive.new_topic_class(false) =~ "rounded-full"
      true
  """
  def new_topic_class(true = _empty),
    do:
      "flex w-full items-center justify-center gap-1.5 rounded-box py-2.5 text-sm font-medium text-muted transition-colors cursor-pointer bg-fill hover:text-base-content focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"

  def new_topic_class(false),
    do: @chip_base <> "text-muted hover:bg-fill hover:text-base-content"
end
