defmodule Bonfire.UI.Groups.GroupSensitiveNoticeTest do
  @moduledoc """
  The page of a group or topic marked sensitive shows a notice in place of its feed, to members and guests alike, and blurs the header's banner and icon until "Continue". Nothing is remembered: the next visit shows the notice again.
  """
  use Bonfire.UI.Groups.ConnCase, async: false
  @moduletag :ui

  alias Bonfire.Classify.Categories
  alias Bonfire.Classify.Simulate
  alias Bonfire.Social.Objects

  setup do
    Process.put([:bonfire, :feed_live_update_many_preload_mode], :inline)
    Process.put(:federating, false)
    account = fake_account!()
    owner = fake_user!(account)

    group = public_group(owner, "Life drawing")
    Simulate.fake_post_in_group!(owner, group, "<p>Tonight's session</p>")

    media = Bonfire.Social.Fake.upload_media(:images, owner)

    {:ok, group} =
      Categories.update(owner, group, %{profile: %{icon_id: media.id, image_id: media.id}})

    %{account: account, owner: owner, group: group, conn: conn(user: owner, account: account)}
  end

  defp public_group(owner, name) do
    Simulate.fake_group!(owner, %{
      name: name,
      membership: "open",
      visibility: "global",
      participation: "anyone",
      default_content_visibility: "public"
    })
  end

  defp group_path(group), do: "/&#{group.character.username}"

  test "a group not marked sensitive shows its feed, with no notice", %{conn: conn, group: group} do
    conn
    |> visit(group_path(group))
    |> wait_async()
    |> assert_has("[data-id=feed]", text: "Tonight's session")
    |> assert_has("[data-role=group-hero-banner]")
    |> refute_has("[data-role=sensitive_group_notice]")
    |> refute_has("[data-role=group-hero-banner][data-sensitive]")
  end

  test "a member of a group marked sensitive sees a notice in place of its feed, and Continue shows the feed",
       %{conn: conn, group: group} do
    assert {:ok, _} = Objects.set_sensitivity(group, true)

    conn
    |> visit(group_path(group))
    |> wait_async()
    |> assert_has("[data-role=sensitive_group_notice]")
    |> refute_has("[data-id=feed]", text: "Tonight's session")
    |> assert_has("[data-role=group-hero-banner][data-sensitive]")
    |> assert_has("[data-role=group-hero-avatar][data-sensitive]")
    |> click_button("[data-role=sensitive_group_notice] button", "Continue")
    |> wait_async()
    |> assert_has("[data-id=feed]", text: "Tonight's session")
    |> refute_has("[data-role=sensitive_group_notice]")
    |> refute_has("[data-role=group-hero-banner][data-sensitive]")
    |> refute_has("[data-role=group-hero-avatar][data-sensitive]")
  end

  test "a guest sees the same notice", %{group: group} do
    assert {:ok, _} = Objects.set_sensitivity(group, true)

    conn()
    |> visit(group_path(group))
    |> wait_async()
    |> assert_has("[data-role=sensitive_group_notice]")
    |> refute_has("[data-id=feed]", text: "Tonight's session")
    |> assert_has("[data-role=group-hero-banner][data-sensitive]")
  end

  test "after Continue, the next visit shows the notice again", %{conn: conn, group: group} do
    assert {:ok, _} = Objects.set_sensitivity(group, true)

    conn
    |> visit(group_path(group))
    |> wait_async()
    |> click_button("[data-role=sensitive_group_notice] button", "Continue")
    |> refute_has("[data-role=sensitive_group_notice]")

    conn
    |> visit(group_path(group))
    |> wait_async()
    |> assert_has("[data-role=sensitive_group_notice]")
  end

  test "a topic marked sensitive shows the notice on its page", %{
    conn: conn,
    owner: owner,
    group: group
  } do
    topic = Simulate.fake_category!(owner, group, %{name: "Figure studies", type: :topic})
    assert {:ok, _} = Objects.set_sensitivity(topic, true)

    conn
    |> visit(path(topic))
    |> wait_async()
    |> assert_has("[data-role=sensitive_group_notice]")
  end

  test "a topic not marked sensitive in a group marked sensitive does not", %{
    conn: conn,
    owner: owner,
    group: group
  } do
    topic = Simulate.fake_category!(owner, group, %{name: "Materials", type: :topic})
    assert {:ok, _} = Objects.set_sensitivity(group, true)
    {:ok, topic} = Categories.get(id(topic), [:default, skip_boundary_check: true])
    refute Categories.sensitive?(topic), "control: the topic has its own mark, which is off"

    conn
    |> visit(path(topic))
    |> wait_async()
    |> refute_has("[data-role=sensitive_group_notice]")
  end
end
