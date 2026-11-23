defmodule Bonfire.UI.Groups.GroupIconTest do
  @moduledoc "The icon and colour a group or topic has picked show on its tile in the groups directory (where an uploaded image comes first), in the sidebar (never the image) and in the page header (a group's and a topic's, the image first), and a group or topic with none keeps its letter tile."
  use Bonfire.UI.Groups.ConnCase, async: false
  @moduletag :ui

  alias Bonfire.Classify.Appearance
  alias Bonfire.Classify.Categories
  alias Bonfire.Classify.Simulate

  @icon "ph:baby-fill"
  @header_tile "[data-role=page_header_icon] [data-role=group_tile]"
  @picked_header_tile "#{@header_tile}[data-icon='#{@icon}']"

  setup do
    Process.put([:bonfire, :feed_live_update_many_preload_mode], :inline)
    Process.put(:federating, false)

    owner = fake_user!(fake_account!())
    account = fake_account!()
    member = fake_user!(account)

    plain =
      Simulate.fake_group!(owner, %{name: "Plain tile", membership: "open", visibility: "global"})

    picked =
      Simulate.fake_group!(owner, %{name: "Picked tile", membership: "open", visibility: "global"})

    {:ok, _} = Appearance.set_icon(picked, @icon, current_user: owner)
    {:ok, _} = Appearance.set_colour(picked, "teal", current_user: owner)

    for group <- [plain, picked],
        do: assert({:ok, _} = Categories.join_and_follow_group(member, group))

    %{owner: owner, member: member, account: account, plain: plain, picked: picked}
  end

  defp as_member(context), do: conn(user: context.member, account: context.account)

  test "the groups directory shows a group's picked icon and colour on its tile, a plain one keeps its letter",
       context do
    picked_card = "#group-preview-#{id(context.picked)}"
    plain_card = "#group-preview-#{id(context.plain)}"

    as_member(context)
    |> visit("/groups/discover")
    |> assert_has("#{picked_card} [data-role=group_tile][data-icon='#{@icon}'].topic-teal")
    |> refute_has("#{picked_card} [data-role=group_tile]", text: "P")
    |> assert_has("#{plain_card} [data-role=group_tile]", text: "P")
    |> refute_has("#{plain_card} [data-role=group_tile][data-icon]")
    |> refute_has("#{plain_card} [data-role=group_tile].topic-teal")
  end

  @tag Bonfire.Common.RuntimeConfig.skip_in_ci()
  @sidebar_row "[data-role=sidebar-groups] [data-role=sidebar-group]"

  defp with_image(context, group) do
    media = Bonfire.Social.Fake.upload_media(:images, context.owner)

    {:ok, group} =
      Categories.update(context.owner, group, %{profile: %{icon_id: media.id, image_id: media.id}})

    group
  end

  # the sidebar row of a group, by the id it ends with
  defp row_of(group), do: "#{@sidebar_row}[id$='-group-#{id(group)}']"

  test "the sidebar row shows a group's picked icon and colour, a plain group's row its letter",
       context do
    {:ok, _} = Bonfire.Social.Pins.pin(context.member, context.picked, nil, to_feeds: [])
    {:ok, _} = Bonfire.Social.Pins.pin(context.member, context.plain, nil, to_feeds: [])

    as_member(context)
    |> visit(Bonfire.Common.URIs.path(context.plain))
    |> wait_async()
    |> assert_has(
      "#{row_of(context.picked)} [data-role=group_tile][data-icon='#{@icon}'].topic-teal",
      timeout: 1_000
    )
    |> assert_has("#{row_of(context.plain)} [data-role=group_tile]", text: "P")
    |> refute_has("#{row_of(context.plain)} [data-role=group_tile][data-icon]")
  end

  @tag Bonfire.Common.RuntimeConfig.skip_in_ci()
  test "a group with an uploaded image and a picked icon: the sidebar row shows the icon, its directory tile and its page header the image",
       context do
    both = with_image(context, context.picked)
    {:ok, _} = Bonfire.Social.Pins.pin(context.member, both, nil, to_feeds: [])

    as_member(context)
    |> visit("/groups/discover")
    |> assert_has("#group-preview-#{id(both)} img[src]")
    |> refute_has("#group-preview-#{id(both)} [data-role=group_tile]")

    as_member(context)
    |> visit(Bonfire.Common.URIs.path(both))
    |> wait_async()
    |> assert_has("[data-role=page_header_icon] img")
    |> refute_has(@header_tile)
    # the sidebar: the picked icon in its colour, and no image
    |> assert_has("#{row_of(both)} [data-role=group_tile][data-icon='#{@icon}'].topic-teal",
      timeout: 1_000
    )
    |> refute_has("#{row_of(both)} img")
    |> refute_has("#{row_of(both)} [style*='background-image']")
  end

  @tag Bonfire.Common.RuntimeConfig.skip_in_ci()
  test "control: a group with an uploaded image and no picked icon has its letter tile in the sidebar, the image on its directory tile and page header",
       context do
    image_only = with_image(context, context.plain)
    {:ok, _} = Bonfire.Social.Pins.pin(context.member, image_only, nil, to_feeds: [])

    as_member(context)
    |> visit("/groups/discover")
    |> assert_has("#group-preview-#{id(image_only)} img[src]")

    as_member(context)
    |> visit(Bonfire.Common.URIs.path(image_only))
    |> wait_async()
    |> assert_has("[data-role=page_header_icon] img")
    |> assert_has("#{row_of(image_only)} [data-role=group_tile]", text: "P", timeout: 1_000)
    |> refute_has("#{row_of(image_only)} [data-role=group_tile][data-icon]")
    |> refute_has("#{row_of(image_only)} img")
    |> refute_has("#{row_of(image_only)} [style*='background-image']")
  end

  test "a group's page header shows its picked icon, a plain group's keeps its letter tile",
       context do
    as_member(context)
    |> visit(Bonfire.Common.URIs.path(context.picked))
    |> wait_async()
    |> assert_has(@picked_header_tile)

    as_member(context)
    |> visit(Bonfire.Common.URIs.path(context.plain))
    |> wait_async()
    |> assert_has(@header_tile, text: "P")
    |> refute_has("#{@header_tile}[data-icon]")
  end

  test "a topic's page header shows the topic's picked icon, else the group's tile", context do
    picked_topic =
      Simulate.fake_category!(context.owner, context.picked, %{name: "Picked topic", type: :topic})

    plain_topic =
      Simulate.fake_category!(context.owner, context.plain, %{name: "Plain topic", type: :topic})

    {:ok, _} = Appearance.set_icon(picked_topic, @icon, current_user: context.owner)

    # the topic's own icon, though its group (the plain one) has none
    plain_group_picked_topic =
      Simulate.fake_category!(context.owner, context.plain, %{name: "Another", type: :topic})

    {:ok, _} =
      Appearance.set_icon(plain_group_picked_topic, "ph:cat-fill", current_user: context.owner)

    as_member(context)
    |> visit(
      Bonfire.Classify.Web.GroupNavigation.topic_path(context.plain, plain_group_picked_topic)
    )
    |> wait_async()
    |> assert_has("#{@header_tile}[data-icon='ph:cat-fill']")

    as_member(context)
    |> visit(Bonfire.Classify.Web.GroupNavigation.topic_path(context.plain, plain_topic))
    |> wait_async()
    |> assert_has(@header_tile, text: "P")
    |> refute_has("#{@header_tile}[data-icon]")

    as_member(context)
    |> visit(Bonfire.Classify.Web.GroupNavigation.topic_path(context.picked, picked_topic))
    |> wait_async()
    |> assert_has(@picked_header_tile)
  end
end
