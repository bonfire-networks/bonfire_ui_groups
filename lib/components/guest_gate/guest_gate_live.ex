defmodule Bonfire.UI.Groups.GuestGateLive do
  @moduledoc """
  What a visitor who is not logged in gets in place of a group's feed when the group's posts are for people with an account.

  Rendered by `Bonfire.UI.Groups.GroupLive` as a stand-in for the timeline component, so it takes the same `header` slot (hero, composer placeholder) and shows the invitation where the feed would be. The decision to show it is made at mount (`guest_gated?` in `Bonfire.Classify.LiveHandler.mounted/3`) from `Bonfire.Classify.Boundaries.guests_may_read_content?/1`.

  Where "join" leads is the instance's business, not the group's: the login page already reads an optional external sign-up URL and a message explaining who can sign in (a gated instance, e.g. one whose members come from Ghost, sets both), so the invitation follows the same two settings rather than growing its own.
  """
  use Bonfire.UI.Common.Web, :stateless_component

  prop category, :any, required: true
  prop permalink, :string, default: nil

  slot header

  @doc """
  The login page, returning to the gated page afterwards. Same `go` query the "you need to log in first" redirect uses, so a person who logs in from here lands back on the group.

      iex> login_path("/&backstage")
      "/login?go=%2F%26backstage"

      iex> login_path(nil)
      "/login"
  """
  def login_path(nil), do: "/login"
  def login_path(permalink), do: "/login?" <> Plug.Conn.Query.encode(go: permalink)

  def external_signup_url,
    do: maybe_apply(Bonfire.UI.Me.LoginLive, :external_signup_url, [], fallback_return: nil)

  def gated_login_message,
    do: maybe_apply(Bonfire.UI.Me.LoginLive, :gated_login_message, [], fallback_return: nil)
end
