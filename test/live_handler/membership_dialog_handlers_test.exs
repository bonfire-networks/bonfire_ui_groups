defmodule Bonfire.UI.Groups.MembershipDialogHandlersTest do
  @moduledoc """
  Joining and leaving from the sidebar, which runs in PersistentLive (`sticky`), not the page.
  """
  use Bonfire.UI.Groups.ConnCase, async: false

  alias Bonfire.Classify.Categories
  alias Bonfire.UI.Groups.LiveHandler
  alias Bonfire.UI.Common.ReusableModalLive

  setup do
    Process.put(:federating, false)
    account = fake_account!()
    user = fake_user!(account)
    creator = fake_user!(account)

    {:ok, group} =
      Categories.create(
        creator,
        %{
          name: Faker.Lorem.sentence(),
          username: "dialogs_#{System.unique_integer([:positive])}",
          type: :group,
          membership: "open",
          visibility: "global"
        },
        true
      )

    %{user: user, group: group}
  end

  test "from the sidebar, the leave dialog opens in PersistentLive's own modal", %{
    user: user,
    group: group
  } do
    LiveHandler.handle_event(
      "open_leave_confirm",
      %{"id" => group.id, "group-name" => "G", "join-mode" => "invite"},
      socket(user, sticky: true, parent_pid: self())
    )

    assert_received {:phoenix, :send_update, {{ReusableModalLive, "persistent_modal"}, assigns}}
    assert assigns.modal_assigns[:join_mode] == "invite"
  end

  test "from a page, the leave dialog opens in the page's modal", %{user: user, group: group} do
    LiveHandler.handle_event(
      "open_leave_confirm",
      %{"id" => group.id, "join-mode" => "request"},
      socket(user)
    )

    assert_received {:phoenix, :send_update, {{ReusableModalLive, "modal"}, assigns}}
    assert assigns.modal_assigns[:join_mode] == "request"
  end

  test "leaving from the sidebar tells the page's Join button and membership assigns", %{
    user: user,
    group: group
  } do
    {:ok, _} = Categories.join_and_follow_group(user, group)
    group_id = group.id

    LiveHandler.handle_event(
      "leave_group",
      %{"id" => group_id},
      socket(user, sticky: true, parent_pid: self())
    )

    refute Map.get(Categories.member_of_groups?(user, [group_id]), group_id, false)

    assert_received {:phoenix, :send_update,
                     {{Bonfire.Classify.Web.JoinButtonLive, "join_btn_" <> ^group_id},
                      %{my_membership: false}}}

    assert_received {{Bonfire.Classify.LiveHandler, :refresh_membership}, ^group_id}

    assert_received {:phoenix, :send_update,
                     {{ReusableModalLive, "persistent_modal"}, %{show: false}}}
  end

  defp socket(user, context \\ []) do
    # on the struct because `assign/3` refuses the reserved `:flash`
    %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, flash: %{}}}
    |> Phoenix.Component.assign(:__context__, Map.new([current_user: user] ++ context))
  end
end
