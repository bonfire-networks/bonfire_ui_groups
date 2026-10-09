defmodule Bonfire.UI.Groups.GroupTopicsNavLive do
  @moduledoc "Group topic links, arranged vertically in the sidebar or horizontally on mobile. Shown when the group has topics; the sidebar version also shows to someone who may create the first one, with a New topic button for them."
  use Bonfire.UI.Common.Web, :stateless_component

  prop group, :any, required: true
  prop topics, :list, default: []
  prop group_return_to, :string, default: "/groups"
  prop inline, :boolean, default: false

  @doc "Whether to offer a New topic button in the sidebar widget (not the mobile strip), see `Bonfire.Classify.can_create_topic?/2`. Decided by the page, once."
  prop can_create_topic, :boolean, default: false

  def show?(topics, can_create_topic), do: (is_list(topics) and topics != []) or can_create_topic

  def topics_label(group),
    do: l("Topics in %{name}", name: e(group, :profile, :name, l("this group")))

  @doc "The topic links, shared by the sidebar widget (`inline: false`) and the mobile strip."
  def topic_links(assigns) do
    ~F"""
    <ul class={if @inline,
      do: "flex min-w-0 gap-2 overflow-x-auto px-2 py-1 [scrollbar-width:thin]",
      else: "flex flex-col"}>
      {#for topic <- @topics}
        <li class={"shrink-0": @inline}>
          <LinkLive
            to={Bonfire.Classify.Web.GroupNavigation.link(path(topic), @group_return_to)}
            opts={[id: "group-topic-#{if @inline, do: "mobile", else: "link"}-#{id(topic)}"]}
            class={
              "flex gap-2 rounded-selector text-sm",
              "items-center px-2 py-3 hover:bg-base-200 active:bg-base-200": @inline,
              "items-start py-3 hover:underline": !@inline
            }
          >
            <#Icon iconify="ph:hash" class="mt-0.5 size-4 shrink-0 text-primary" />
            <span class={if @inline, do: "max-w-[14rem] truncate", else: "min-w-0 break-words"}>{e(topic, :profile, :name, l("Untitled topic"))}</span>
          </LinkLive>
        </li>
      {/for}
    </ul>
    """
  end
end
