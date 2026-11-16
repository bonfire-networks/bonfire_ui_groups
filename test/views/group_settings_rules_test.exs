defmodule Bonfire.UI.Groups.GroupSettingsRulesTest do
  @moduledoc "A group's rules tab: the instance's rules show there as ticked and can't be unticked, the group can tick the others, and the group can reorder its rules without touching the instance's order."
  use Bonfire.UI.Groups.ConnCase, async: false
  use Bonfire.Common.Settings
  @moduletag :ui

  alias Bonfire.Classify.Simulate
  alias Bonfire.CommunityRules

  @template [
    behavior: [
      name: "Behavior",
      sections: [
        civility: [
          name: "Civility",
          rules: [
            be_respectful: %{name: "Be respectful"},
            no_spam: %{name: "No spam", has_qualifier: true}
          ]
        ]
      ]
    ]
  ]

  setup do
    Settings.put([:bonfire_community_rules, :template_rules], @template,
      scope: :instance,
      skip_boundary_check: true
    )

    {:ok, _} =
      CommunityRules.save_rules(
        Settings.instance_scope(),
        %{"civility" => %{"be_respectful" => %{}}},
        %{"rules" => %{"civility" => ["be_respectful", "no_spam"]}}
      )

    account = fake_account!()
    owner = fake_user!(account)

    group =
      Simulate.fake_group!(owner, %{
        name: "Trail runners",
        membership: "open",
        visibility: "global"
      })

    {:ok, conn: conn(user: owner, account: account), group: group}
  end

  defp tab(conn, group) do
    conn
    |> visit("/&#{group.character.username}/settings/rules")
    |> click_button("#group-rules-#{group.id}-section-header-civility", "Civility")
  end

  defp group_info(group), do: CommunityRules.get_extra_info_by_id(group.id).info || %{}

  test "an instance rule shows ticked and can't be unticked, while the other rules can be", %{
    conn: conn,
    group: group
  } do
    b = "#group-rules-#{group.id}"

    session =
      conn
      |> tab(group)
      |> assert_has("#{b}-rule-check-civility-be_respectful[checked][disabled]")
      |> refute_has("#{b}-rule-check-civility-no_spam[checked]")
      |> refute_has("#{b}-rule-check-civility-no_spam[disabled]")

    # the disabled box doesn't stop a crafted event, so the server ignores it too
    session
    |> unwrap(fn view ->
      Phoenix.LiveViewTest.render_hook(
        Phoenix.LiveViewTest.element(view, "#{b}-rules-civility"),
        "toggle_rule",
        %{"key" => "civility:be_respectful"}
      )
    end)
    |> assert_has("#{b}-rule-check-civility-be_respectful[checked][disabled]")
    |> check("#{b}-rule-check-civility-no_spam", "No spam", exact: false)
    |> assert_has("#{b}-rule-check-civility-no_spam[checked]")

    assert get_in(group_info(group), ["rules", "civility", "no_spam"]) == %{}
    refute get_in(group_info(group), ["rules", "civility", "be_respectful"])
  end

  test "the group's order starts from the instance's, and a change saves to the group only", %{
    conn: conn,
    group: group
  } do
    b = "#group-rules-#{group.id}"

    conn
    |> tab(group)
    |> assert_has("#{b}-rules-civility > :first-child", text: "Be respectful")
    |> click_button("#{b}-move-rule-civility-be_respectful-down", "")
    |> assert_has("#{b}-rules-civility > :first-child", text: "No spam")

    # `Settings.put` merges the test template into the configured one, so civility has more rules after these two
    assert group_info(group)["rules_order"]["rules"]["civility"] |> Enum.take(2) ==
             ["no_spam", "be_respectful"]

    assert CommunityRules.get_extra_info_for_instance().info["rules_order"]["rules"]["civility"] ==
             ["be_respectful", "no_spam"]
  end
end
