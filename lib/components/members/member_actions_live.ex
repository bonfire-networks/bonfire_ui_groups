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

  def name(person),
    do: e(person, :profile, :name, nil) || e(person, :character, :username, l("this member"))
end
