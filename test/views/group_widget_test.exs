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
        civility: [
          name: "Civility",
          rules: [
            be_respectful: %{name: "Be respectful"},
            no_spam: %{name: "No spam"},
            no_attacks: %{name: "No attacks"}
          ]
        ]
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
      # a guest has no LiveView socket, so the page they get is the static render, which `visit` does not give (it connects a LiveView)
      # conn()
      # |> visit(group_path(ctx.group))
      conn()
      |> get_conn_render(group_path(ctx.group))
      |> assert_has(".sidebar-widgets #{@widget}")
      |> refute_has("[data-id=main_section] #{@widget}")
    end
  end

  describe "About" do
    test "holds the access details, which leave the header", ctx do
      session =
        as_creator(ctx)
        |> visit(group_path(ctx.group))

      for label <- ["Find group", "Join", "Post", "See content"] do
        assert_has(session, "#{@widget} [data-role=group-access-list] dt",
          text: label,
          exact: true
        )
      end

      session
      |> assert_has("#{@widget} [data-role=group-widget-membership]", text: "Join")
      |> assert_has("#{@widget} [data-role=group-widget-default_content_visibility]",
        text: "See content"
      )
      |> refute_has("[data-id=group_hero] [data-role=group-access-list]")
      |> assert_has("#{@widget} [data-role=group-widget-created]")
    end

    # the header shows no join or visibility policy; both are in the widget
    test "visitors see how to join and who can see it only in the widget", ctx do
      # a guest has no LiveView socket, so the page they get is the static render, which `visit` does not give (it connects a LiveView)
      # conn()
      # |> visit(group_path(ctx.group))
      conn()
      |> get_conn_render(group_path(ctx.group))
      |> refute_has("[data-id=group_hero] [data-role=group-hero-membership]")
      |> assert_has("#{@widget} [data-role=group-widget-membership]")
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

  # the three preview options say "preview" and who gets it, so the settings form reads them as one family
  describe "About, preview visibility" do
    test "a group local users can preview says so" do
      account = fake_account!()
      me = fake_user!(account)

      group =
        Simulate.fake_group!(me, %{
          name: "Local preview",
          membership: "local:members",
          visibility: "local:preview",
          participation: "group_members",
          default_content_visibility: "local"
        })

      {:ok, view, _html} =
        live(conn(user: me, account: account), "/group/#{group.character.username}")

      assert has_element?(
               view,
               "#{@widget} [data-role=group-widget-visibility] dd",
               "Users of this instance can preview"
             )
    end

    # not selectable until groups federate, so no group can be made with it here
    test "the federated preview option says anyone can preview" do
      assert %{label: "Anyone can preview"} =
               Bonfire.Boundaries.Presets.dimension_meta(:visibility, "preview")
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
               "[data-id=group_widget] [data-role=group-widget-default_content_visibility] dd",
               "Users of this instance (by default)"
             )

      # the description is the value's tooltip
      assert has_element?(
               view,
               "[data-id=group_widget] [data-role=group-widget-default_content_visibility] dd[title*='Posts visible to logged-in users on this instance']"
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
               "[data-id=group_widget] [data-role=group-widget-default_content_visibility] dt",
               "See content"
             )

      assert has_element?(
               view,
               "[data-id=group_widget] [data-role=group-widget-default_content_visibility] dd[title^='Posts visible to']"
             )
    end
  end

  describe "Rules" do
    setup do
      # the instance's rules are cached, and the cache isn't rolled back with the DB sandbox
      Bonfire.Common.Cache.reset({Bonfire.CommunityRules, :load_instance_rules_sections}, [])
      Bonfire.Common.Cache.reset({Bonfire.CommunityRules, :get_extra_info_for_instance}, [])
      :ok
    end

    test "are left out when neither the group nor the instance has any", ctx do
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

    test "put all the instance's rules in a closed fold, under the group's own, in the order each one set",
         ctx do
      own = "#{@widget} [data-role=group-widget-own-rules]"
      fold = "#{@widget} details[data-role=group-widget-instance-rules]:not([open])"

      Settings.put([:bonfire_community_rules, :template_rules], @rules_template,
        scope: :instance,
        skip_boundary_check: true
      )

      {:ok, _} =
        Bonfire.CommunityRules.save_rules(
          Bonfire.Common.Settings.instance_scope(),
          %{"civility" => %{"be_respectful" => %{}}},
          %{"rules" => %{"civility" => ["no_attacks", "no_spam", "be_respectful"]}}
        )

      # the group has none of its own yet: the Rules heading and the fold only
      as_creator(ctx)
      |> visit(group_path(ctx.group))
      |> assert_has("#{@widget} [data-role=group-widget-rules] h3", text: "Rules")
      |> assert_has(fold, text: "Be respectful")
      |> refute_has(own)

      {:ok, _} =
        Bonfire.CommunityRules.save_rules(id(ctx.group), %{
          "civility" => %{"be_respectful" => %{}, "no_spam" => %{}, "no_attacks" => %{}}
        })

      # a rule the instance also has shows in the fold only, and the group follows the instance's order
      as_creator(ctx)
      |> visit(group_path(ctx.group))
      |> assert_has(fold, text: "Be respectful")
      |> refute_has(own, text: "Be respectful")
      |> assert_has("#{own} li:first-child", text: "No attacks")
      |> assert_has("#{own} li:last-child", text: "No spam")

      {:ok, _} =
        Bonfire.CommunityRules.save_rules(id(ctx.group), %{}, %{
          "rules" => %{"civility" => ["no_spam", "no_attacks"]}
        })

      # once the group sets an order of its own, it uses that one
      as_creator(ctx)
      |> visit(group_path(ctx.group))
      |> assert_has("#{own} li:first-child", text: "No spam")
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
