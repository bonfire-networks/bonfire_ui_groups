defmodule Bonfire.UI.Groups.GroupHeroActionsLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop group, :any, required: true
  prop permalink, :any, default: nil
  prop moderators, :list, default: []
  prop my_membership, :any, default: false
  prop membership_slug, :string, default: nil
  prop group_return_to, :string, default: "/groups"

  @doc "The viewer's pin state for the ⋯ menu: `instance`, `sidebar` and `can_pin_instance`, from `Bonfire.Classify.LiveHandler`."
  prop pins, :map, default: %{instance: false, sidebar: false, can_pin_instance: false}

  def render(assigns) do
    assigns
    |> assign(
      variant: Bonfire.UI.Groups.GroupHeroLive.variant(assigns.my_membership),
      moderator:
        Bonfire.UI.Groups.GroupHeroLive.moderator?(
          current_user_id(assigns[:__context__]),
          assigns.moderators
        )
    )
    |> render_sface()
  end

  @doc """
  The follow button's props: a round icon beside Join for visitors ("Follow without joining", a real choice before joining), a row in ⋯ for members. Rendered in one place or the other, never both, so it keeps one id.

      iex> Bonfire.UI.Groups.GroupHeroActionsLive.follow_button_props(%{id: "01M5A1RS1M5A1RS1M5A1RS1M5"}, "visitor")[:hide_text]
      true
      iex> Bonfire.UI.Groups.GroupHeroActionsLive.follow_button_props(%{id: "01M5A1RS1M5A1RS1M5A1RS1M5"}, "member")[:verb]
      "Follow group"
  """
  def follow_button_props(group, variant) do
    verb = if variant == "visitor", do: l("Follow without joining"), else: l("Follow group")

    [
      object_id: id(group),
      object: group,
      path: path(group),
      verb: verb,
      verb_undo: l("Unfollow group"),
      verb_already: l("Unfollow group"),
      title: verb,
      title_already: l("Unfollow group"),
      icon: "ph:rss",
      icon_already: "ph:rss",
      icon_class: "size-4 shrink-0",
      with_bell: false
    ] ++
      if variant == "visitor",
        do: [
          container_class: "inline-flex",
          class: round_button_class(),
          class_already: round_button_class(true),
          hide_text: true
        ],
        else: [
          container_class: "flex w-full",
          class: "flex items-center gap-3 w-full text-sm text-muted",
          class_already: "flex items-center gap-3 w-full text-sm text-primary",
          hide_text: false
        ]
  end

  @doc """
  The round icon buttons' classes, with `active` for a state that is on (following, bell on).

      iex> Bonfire.UI.Groups.GroupHeroActionsLive.round_button_class() =~ "text-base-content"
      true
      iex> Bonfire.UI.Groups.GroupHeroActionsLive.round_button_class(true) =~ "text-primary"
      true
  """
  def round_button_class(active \\ false),
    do:
      "btn btn-circle size-10 min-h-0 border border-divider bg-transparent shadow-none hover:bg-base-200 " <>
        if(active, do: "text-primary", else: "text-base-content")
end
