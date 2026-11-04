defmodule Bonfire.UI.Groups.GroupBioTest do
  @moduledoc """
  A group's bio is written in markdown (or arrives as HTML from a server we mirror it from), so it is rendered wherever it is shown in full, with its links and bare URLs as links, and rendered then made plain where it is clamped to a line or two, so it reads as text rather than as markup.
  """
  use Bonfire.UI.Groups.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  # a real TLD: bare URLs are linked by the formatter when the bio is saved, which checks the TLD in tests too and leaves a `.local` host as text
  @bio "We read **slowly**, see [our reading list](https://example.com/list) or https://example.com/notes"

  setup do
    account = fake_account!()
    creator = fake_user!(account)

    group =
      Bonfire.Classify.Simulate.fake_group!(creator, %{
        name: "Slow readers",
        summary: @bio,
        membership: "open",
        visibility: "global"
      })

    {:ok, conn: conn(user: creator, account: account), group: group}
  end

  test "the About page renders the bio, with its links", %{conn: conn, group: group} do
    conn
    |> visit("/&#{group.character.username}/about")
    |> assert_has("a[href='https://example.com/list']", text: "our reading list")
    |> assert_has("a[href='https://example.com/notes']")
    |> assert_has("strong", text: "slowly")
    |> refute_has("*", text: "**slowly**")
  end

  test "the groups directory renders the bio, with its links", %{conn: conn} do
    conn
    |> visit("/groups")
    |> assert_has("a[href='https://example.com/list']", text: "our reading list")
  end

  test "the settings header shows the bio as plain text", %{conn: conn, group: group} do
    conn
    |> visit("/&#{group.character.username}/settings")
    |> assert_has("p", text: "We read slowly, see our reading list")
    |> refute_has("p", text: "**slowly**")
    |> refute_has("p", text: "](https://example.com/list)")
  end
end
