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

  describe "a topic the viewer can only preview" do
    @summary "A topic summary only members should read"

    setup context do
      {group, topic} = restricted_topic(context.owner, "on_request")
      media = Bonfire.Social.Fake.upload_media(:images, context.owner)

      {:ok, group} =
        Bonfire.Classify.Categories.update(context.owner, group, %{
          profile: %{icon_id: media.id, image_id: media.id}
        })

      {:ok, _} =
        Bonfire.Classify.Categories.update(context.owner, topic, %{profile: %{summary: @summary}})

      member_account = fake_account!()
      member = fake_user!(member_account)

      {:ok, _} =
        Bonfire.Classify.Categories.add_member(context.owner, group, id(member),
          skip_boundary_check: true
        )

      %{group: group, topic: topic, member: member, member_account: member_account}
    end

    test "a member of the group sees the topic with its description", context do
      conn(user: context.member, account: context.member_account)
      |> visit(topic_path(context.topic))
      |> wait_async()
      |> refute_has("#topic_access_gate")
      |> assert_has("[data-role=group-topic-summary]", text: @summary)
    end

    test "a preview viewer sees the parent group's minimal header, no description, and the gate's actions",
         context do
      conn(user: context.visitor, account: context.account)
      |> visit(topic_path(context.topic))
      |> wait_async()
      |> assert_has("#topic_access_gate h1", text: "Restricted topic")
      |> assert_has("#topic_access_gate [data-id=group_hero][data-compact]")
      |> refute_has("[data-role=group-hero-toggle]")
      |> refute_has("[data-role=group-hero-banner]")
      |> refute_has("#topic_access_gate img.size-full")
      |> refute_has("main", text: @summary)
      |> assert_has("#topic_access_gate a", text: "View group")
      |> assert_has("#topic_access_gate button", text: "Request to join")
      |> refute_has("[data-role=group-hero-actions]")
    end

    test "a guest gets the same", context do
      conn()
      |> visit(topic_path(context.topic))
      |> wait_async()
      |> assert_has("#topic_access_gate [data-id=group_hero][data-compact]")
      |> refute_has("[data-role=group-hero-banner]")
      |> refute_has("#topic_access_gate img.size-full")
      |> refute_has("main", text: @summary)
    end
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
