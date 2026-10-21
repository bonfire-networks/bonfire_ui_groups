defmodule Bonfire.UI.Groups.GroupWidgetTest do
  @moduledoc """
  The group widget (`Bonfire.UI.Groups.WidgetGroupLive`): one card replacing the About, Rules and Moderators widgets, with About (the access details, moved out of the header), Rules and Moderators.

  It is in the right rail (the drawer on a phone) for everyone. Visitors also get the short access line in the header, which is what decides whether they can join.
  """
  use Bonfire.UI.Groups.ConnCase, async: false
  use Bonfire.Common.Settings
  @moduletag :ui

  doctest Bonfire.UI.Groups.WidgetGroupLive

  alias Bonfire.Classify.Simulate
  alias Bonfire.Classify.Categories

  @widget "[data-id=group_widget]"

  @rules_template [
    behavior: [
      name: "Behavior",
      sections: [
        civility: [name: "Civility", rules: [be_respectful: %{name: "Be respectful"}]]
      ]
    ]
  ]

  setup do
    account = fake_account!()
    creator = fake_user!(account, %{name: "Carla Creator"})

    group =
      Simulate.fake_group!(creator, %{
        name: "Trail runners",
        membership: "open",
        visibility: "global",
        participation: "group_members",
        default_content_visibility: "public"
      })

    %{account: account, creator: creator, group: group}
  end

  defp group_path(group), do: "/group/#{group.character.username}"
  defp as_creator(ctx), do: conn(user: ctx.creator, account: ctx.account)

  describe "placement" do
    test "a member finds one group widget in the sidebar, replacing About and Moderators", ctx do
      as_creator(ctx)
      |> visit(group_path(ctx.group))
      |> assert_has(".sidebar-widgets #{@widget}")
      |> refute_has("[data-id=main_section] #{@widget}")
    end

    # visitors get it there too, so the header isn't followed by a block of reference material
    test "a visitor finds it in the sidebar too, not under the header", ctx do
      conn()
      |> visit(group_path(ctx.group))
      |> assert_has(".sidebar-widgets #{@widget}")
      |> refute_has("[data-id=main_section] #{@widget}")
    end
  end

  describe "About" do
    test "holds the access details, which leave the header", ctx do
      session =
        as_creator(ctx)
        |> visit(group_path(ctx.group))

      for label <- ["Joining ·", "Visibility ·", "Posting ·", "Default post visibility ·"] do
        assert_has(session, "#{@widget} [data-role=group-access-details-content] dt", text: label)
      end

      session
      |> assert_has("#{@widget} [data-role=group-widget-membership]", text: "Joining")
      |> assert_has("#{@widget} [data-role=group-widget-default_content_visibility]",
        text: "New posts"
      )
      |> refute_has("[data-id=group_hero] [data-role=group-access-details-content]")
      |> assert_has("#{@widget} [data-role=group-widget-created]")
    end

    # the header keeps only how to join, which changes what a visitor does next; who can see the group is in the widget
    test "visitors see how to join in the header, and who can see it only in the widget", ctx do
      conn()
      |> visit(group_path(ctx.group))
      |> assert_has("[data-id=group_hero] [data-role=group-hero-membership]")
      |> refute_has("[data-id=group_hero] [data-role=group-hero-visibility]")
      |> assert_has("#{@widget} [data-role=group-widget-visibility]")
    end

    test "a nested group links to the group it is part of", ctx do
      {:ok, subgroup} =
        Categories.create(ctx.creator, %{
          name: "Night runs",
          type: :group,
          parent_category: ctx.group
        })

      as_creator(ctx)
      |> visit(group_path(subgroup))
      |> assert_has("#{@widget} [data-role=group-widget-parent] a", text: "Trail runners")
    end
  end

  describe "About, the stored default post visibility" do
    # Who can read what members post is what a member most needs before writing: the other rows say who can join, see and post, not who the posts reach. Moved from `group_hero_toolbar_test.exs` with the details.
    test "access details say who can read posts, from the group's stored default" do
      account = fake_account!()
      me = fake_user!(account)

      group =
        Bonfire.Classify.Simulate.fake_group!(me, %{
          name: "Backstage",
          membership: "local:members",
          visibility: "nonfederated",
          participation: "local:contributors",
          default_content_visibility: "local"
        })

      {:ok, view, _html} =
        live(conn(user: me, account: account), "/group/#{group.character.username}")

      assert has_element?(
               view,
               "[data-id=group_widget] [data-role=group-access-details-content] dt",
               "Default post visibility · Users of this instance"
             )

      assert has_element?(
               view,
               "[data-id=group_widget] [data-role=group-access-details-content] dd",
               "Posts visible to logged-in users on this instance"
             )
    end

    # `Bonfire.Classify.Boundaries.init_boundaries/4` derives and stores a default for every group created here, so a group that states none still has one to show. The row only disappears for a group with nothing stored (an old one, or a mirrored remote community), which the factory cannot produce.
    test "access details show the derived default for a group that stated none" do
      account = fake_account!()
      me = fake_user!(account)
      group = Bonfire.Classify.Simulate.fake_group!(me, %{name: "No stated default"})

      {:ok, view, _html} =
        live(conn(user: me, account: account), "/group/#{group.character.username}")

      assert has_element?(
               view,
               "[data-id=group_widget] [data-role=group-access-details-content] dt",
               "Default post visibility ·"
             )

      assert has_element?(
               view,
               "[data-id=group_widget] [data-role=group-access-details-content] dd",
               "Posts visible to"
             )
    end
  end

  describe "Rules" do
    test "are left out when the group has none", ctx do
      as_creator(ctx)
      |> visit(group_path(ctx.group))
      |> assert_has(@widget)
      |> refute_has("#{@widget} [data-role=group-widget-rules]")
    end

    test "list the group's rules", ctx do
      Settings.put([:bonfire_community_rules, :template_rules], @rules_template,
        scope: :instance,
        skip_boundary_check: true
      )

      {:ok, _} =
        Bonfire.CommunityRules.save_rules(id(ctx.group), %{
          "civility" => %{"be_respectful" => %{}}
        })

      as_creator(ctx)
      |> visit(group_path(ctx.group))
      |> assert_has("#{@widget} [data-role=group-widget-rules]", text: "Be respectful")
    end
  end

  describe "Moderators" do
    # messaging the moderators is separate work (modmail), not a button here
    test "lists the moderators, with no Message moderators button", ctx do
      as_creator(ctx)
      |> visit(group_path(ctx.group))
      |> assert_has("#{@widget} [data-role=group-sidebar-moderators]", text: "Carla Creator")
      |> refute_has(@widget, text: "Message moderators")
    end

    # a topic's page is about its group, so the widget names who moderates the group, not whoever started the topic
    test "on a topic page, lists the group's moderators", ctx do
      member = fake_user!(fake_account!(), %{name: "Mo Member"})
      {:ok, _} = Categories.join_and_follow_group(member, ctx.group)
      topic = Simulate.fake_category!(member, ctx.group, %{name: "Race reports", type: :topic})

      as_creator(ctx)
      |> visit(group_path(ctx.group) <> "/topic/" <> topic.character.username)
      |> assert_has("#{@widget} [data-role=group-sidebar-moderators]", text: "Carla Creator")
      |> refute_has("#{@widget} [data-role=group-sidebar-moderators]", text: "Mo Member")
    end
  end
end
