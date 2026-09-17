defmodule Bonfire.UI.Groups.AccessGateLive do
  @moduledoc "Shows the group hero and an access notice when upstream grants see but not read."
  use Bonfire.UI.Common.Web, :stateless_component

  prop permalink, :string, default: nil
  slot header

  @doc """
  Returns to the group after signing in, without promising access.

      iex> login_path("/&backstage")
      "/login?go=%2F%26backstage"

      iex> login_path(nil)
      "/login"
  """
  def login_path(nil), do: "/login"
  def login_path(permalink), do: "/login?" <> Plug.Conn.Query.encode(go: permalink)
end
