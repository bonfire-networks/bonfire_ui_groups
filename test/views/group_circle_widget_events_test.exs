defmodule Bonfire.UI.Groups.GroupCircleWidgetEventsTest do
  @moduledoc "A group's moderators circle changes only through the group's own moderation flow (promote, demote, the keep-a-moderator rule). The add-to-circles widget on any profile accepts a circle id from its event params, so a crafted event must not reach a group's circle."
  use Bonfire.UI.Groups.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  alias Bonfire.Boundaries.Circles
  alias Bonfire.Classify.{Categories, Simulate}

  setup do
    Process.put(:federating, false)

    creator = fake_user!(fake_account!())
    account = fake_account!()
    attacker = fake_user!(account)
    profile_owner = fake_user!(fake_account!())
    group = Simulate.fake_group!(creator, %{membership: "open"})
    {:ok, moderators_circle} = Categories.moderators_circle(group)

    assert Circles.is_encircled_by?(creator, moderators_circle),
           "control: the creator moderates the group to begin with"

    refute Circles.is_encircled_by?(attacker, moderators_circle),
           "control: the attacker does not"

    {:ok,
     creator: creator,
     account: account,
     attacker: attacker,
     profile_owner: profile_owner,
     moderators_circle: moderators_circle}
  end

  defp push_widget(user, account, profile_owner, event, params) do
    {:ok, view, _html} =
      live(conn(user: user, account: account), "/@#{profile_owner.character.username}")

    view
    |> element(
      "[data-id=profile_main_actions] [data-role=open_modal][aria-label='Add to circles']"
    )
    |> render_click()

    [id] =
      view
      |> render()
      |> Floki.parse_document!()
      |> Floki.attribute("[id]", "id")
      |> Enum.filter(&(&1 =~ ~r/add.to.circle.widget/i))
      |> Enum.uniq()
      |> Enum.take(1)

    view
    |> with_target("##{id}")
    |> render_click(event, params)
  end

  test "I cannot take the last moderator out of a group's moderators circle", %{
    creator: creator,
    account: account,
    attacker: attacker,
    profile_owner: profile_owner,
    moderators_circle: moderators_circle
  } do
    push_widget(attacker, account, profile_owner, "remove", %{
      "id" => creator.id,
      "circle" => moderators_circle.id
    })

    assert Circles.is_encircled_by?(creator, moderators_circle)
  end

  test "I cannot make myself a moderator of a group", %{
    account: account,
    attacker: attacker,
    profile_owner: profile_owner,
    moderators_circle: moderators_circle
  } do
    push_widget(attacker, account, profile_owner, "add", %{
      "id" => attacker.id,
      "circle" => moderators_circle.id
    })

    refute Circles.is_encircled_by?(attacker, moderators_circle)
  end
end
