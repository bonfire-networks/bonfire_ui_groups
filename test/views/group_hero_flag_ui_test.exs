defmodule Bonfire.UI.Groups.GroupHeroFlagUITest do
  @moduledoc """
  Reporting a group from the menu in its hero: the item opens the flag form, and submitting it puts the group in the moderators' queue.
  """
  use Bonfire.UI.Groups.ConnCase, async: false
  @moduletag :ui

  alias Bonfire.Classify.Simulate

  setup do
    Process.put(:federating, false)

    creator = fake_user!(fake_account!())
    reporter_account = fake_account!()
    reporter = fake_user!(reporter_account)

    group =
      Simulate.fake_group!(creator, %{
        name: "Group to report",
        membership: "open",
        visibility: "global",
        participation: "anyone",
        default_content_visibility: "public"
      })

    {:ok, group: group, reporter: reporter, conn: conn(user: reporter, account: reporter_account)}
  end

  test "the hero's Flag item opens the form, and submitting it flags the group", %{
    conn: conn,
    group: group,
    reporter: reporter
  } do
    refute Bonfire.Social.Flags.flagged?(reporter, group), "control: not flagged yet"

    conn
    |> visit("/group/#{group.character.username}")
    |> wait_async()
    |> click_button("[data-role=open_modal]", "Flag Group to report")
    |> fill_in("Add a comment for the flag", with: "against the rules")
    |> click_button("[data-role=submit_flag]", "Flag Group to report")

    assert Bonfire.Social.Flags.flagged?(reporter, group)
  end

  # the hero shows other things to a member (the status, a Leave item), so the menu is checked for them too
  test "a member of the group can flag it from the hero too", %{
    conn: conn,
    group: group,
    reporter: reporter
  } do
    {:ok, _} = Bonfire.Classify.Categories.join_and_follow_group(reporter, group)
    assert Bonfire.Classify.Categories.member?(reporter, group), "control: a member"

    conn
    |> visit("/group/#{group.character.username}")
    |> wait_async()
    |> click_button("[data-role=open_modal]", "Flag Group to report")
    |> fill_in("Add a comment for the flag", with: "against the rules")
    |> click_button("[data-role=submit_flag]", "Flag Group to report")

    assert Bonfire.Social.Flags.flagged?(reporter, group)
  end
end
