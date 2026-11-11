defmodule Bonfire.UI.Groups.MemberActionsLive do
  @moduledoc """
  What a group's moderators can do about one of its members, from a members list: ghost, silence and block them in the group, and remove them from it. Shared by the members page and the members list in the group's settings, which differ only in where the remove event goes (`event` and `target`).

  Offer it only to someone who may moderate the group (`:mediate`) and for somebody other than themselves, as the lists do.
  """
  use Bonfire.UI.Common.Web, :stateless_component

  prop category, :any, required: true
  prop person, :any, required: true
  prop parent_id, :string, required: true
  prop event, :string, default: "Bonfire.UI.Groups:remove_member"
  prop target, :any, default: nil

  @doc "Whether the person already moderates the group"
  prop moderator?, :boolean, default: false

  @doc "Whether the group is hosted here (`Categories.hosted_here?/1`), worked out once per list: a mirror's moderators are managed at its origin, so neither moderator item is offered"
  prop hosted_here?, :boolean, default: false

  @doc "The group's custodian, who is never demoted from here (as the Moderators card has it), worked out once per list"
  prop custodian_id, :string, default: nil

  prop make_moderator_event, :string, default: "Bonfire.UI.Groups:make_moderator"
  prop remove_moderator_event, :string, default: "Bonfire.UI.Groups:remove_moderator"

  def name(person),
    do: e(person, :profile, :name, nil) || e(person, :character, :username, l("this member"))
end
