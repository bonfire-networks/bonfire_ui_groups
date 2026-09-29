defmodule Bonfire.UI.Groups.TopicAccessGateTest do
  use Bonfire.UI.Groups.ConnCase, async: false
  @moduletag :ui

  alias Bonfire.Classify.Simulate

  setup do
    Process.put(:federating, false)
    owner = fake_user!()
    account = fake_account!()
    visitor = fake_user!(account)
    %{owner: owner, account: account, visitor: visitor}
  end

  for {label, path_fun} <- [topic: :topic_path, group_alias: :group_alias_path] do
    test "restricted topic offers parent membership through #{label}", context do
      {group, topic} = restricted_topic(context.owner, "on_request")

      conn(user: context.visitor, account: context.account)
      |> visit(apply(__MODULE__, unquote(path_fun), [topic]))
      |> wait_async()
      |> assert_has("#topic_access_gate h1", text: "Restricted topic")
      |> assert_has("#topic_access_gate a", text: "View group")
      |> assert_has("#topic_access_gate button", text: "Request to join")
      |> refute_has("#topic_access_gate button", text: "Follow")
      |> refute_has("[data-id=feed]")
      |> refute_has("#inline_composer_placeholder")
      |> click_button("#join_btn_#{group.id}", "Request to join")
      |> wait_async()
      |> assert_has("#topic_access_gate button", text: "Pending")
    end
  end

  test "invite-only topic links to its parent without misleading follow or join actions",
       context do
    {_group, topic} = restricted_topic(context.owner, "invite_only")

    conn(user: context.visitor, account: context.account)
    |> visit("/+#{topic.character.username}")
    |> wait_async()
    |> assert_has("#topic_access_gate a", text: "View group")
    |> refute_has("#topic_access_gate button")
    |> refute_has("[data-id=feed]")
  end

  test "guest sign-in retains the topic destination", context do
    {_group, topic} = restricted_topic(context.owner, "on_request")

    conn()
    |> visit("/+#{topic.character.username}")
    |> wait_async()
    |> assert_has(
      "#topic_access_gate a[href='/login?go=%2F%2B#{topic.character.username}']",
      text: "Sign in"
    )
    |> refute_has("#topic_access_gate button")
    |> refute_has("[data-id=feed]")
  end

  def topic_path(topic), do: "/+#{topic.character.username}"
  def group_alias_path(topic), do: "/&#{topic.id}"

  defp restricted_topic(owner, membership) do
    group =
      Simulate.fake_group!(owner, %{
        name: "Preview parent",
        membership: membership,
        visibility: "nonfederated:preview",
        participation: "group_members",
        default_content_visibility: "members:private"
      })

    topic = Simulate.fake_category!(owner, group, %{type: :topic, name: "Restricted topic"})
    {group, topic}
  end
end
