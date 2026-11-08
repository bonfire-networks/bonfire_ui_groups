defmodule Bonfire.UI.Groups.GroupSettingsAutoBellTest do
  @moduledoc """
  The group settings' instance tab has two toggles for new accounts: auto-join, and turning on notifications for the group's new posts. Only instance admins see them.
  """
  use Bonfire.UI.Groups.ConnCase, async: false
  @moduletag :ui

  alias Bonfire.Classify.Categories
  alias Bonfire.Classify.Simulate

  setup do
    # `:after_signup_hooks` is instance config in Application env, which the sandbox doesn't roll back
    Bonfire.Common.Config.delete([Bonfire.Me.Users, :after_signup_hooks])
    on_exit(fn -> Bonfire.Common.Config.delete([Bonfire.Me.Users, :after_signup_hooks]) end)

    account = fake_account!()
    admin = fake_admin!(account)
    group = Simulate.fake_group!(admin, %{name: "Support circle"})

    {:ok, account: account, admin: admin, group: group}
  end

  test "an admin turns notifications on for new users, next to auto-join", %{
    account: account,
    admin: admin,
    group: group
  } do
    conn(user: admin, account: account)
    |> visit("/&#{group.character.username}/settings/instance")
    |> assert_has("#group_settings_auto_join_form", text: "Auto-join new users")
    |> assert_has("#group_settings_auto_bell_form", text: "Turn on notifications for new users")
    # the label also holds the help text
    |> check("#group_settings_auto_bell_form input[name=enabled]", "Turn on notifications for new users",
      exact: false
    )

    assert Categories.auto_bell_new_users?(group)
    refute Categories.auto_join_new_users?(group)
  end

  test "someone who isn't an instance admin doesn't get the toggle", %{group: group} do
    account = fake_account!()
    user = fake_user!(account)

    conn(user: user, account: account)
    |> visit("/&#{group.character.username}/settings/instance")
    |> refute_has("#group_settings_auto_bell_form")
  end
end
