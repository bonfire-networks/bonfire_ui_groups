defmodule Bonfire.UI.Groups.GroupNavigationTest do
  use Bonfire.UI.Groups.ConnCase, async: false
  @moduletag :ui
  doctest Bonfire.Classify.Web.GroupNavigation

  test "sidebar always shows the groups section and its group links" do
    account = fake_account!()
    me = fake_user!(account)

    group =
      Bonfire.Classify.Simulate.fake_group!(me, %{
        membership: "local:members",
        visibility: "nonfederated",
        participation: "local:contributors"
      })

    {:ok, _} = Bonfire.Social.Pins.pin(me, group, nil, to_feeds: [])
    section = "[data-role='sidebar-groups']"

    conn(user: me, account: account)
    |> visit("/group/#{group.character.username}")
    |> assert_has("#{section} [data-role='sidebar-group']", timeout: 1_000)
    # the section's heading is the link to all groups (it replaced an "All groups" item)
    |> assert_has("#{section} a[href='/groups']", text: "Groups", count: 1)
    |> assert_has("#{section} [data-role='group_tile']")
    # no collapse toggle: the group rows aren't inside a <details>
    |> refute_has("details [data-role='sidebar-group']")
  end

  # the sidebar lives in PersistentLive, not the page, and hears of pins from `Pins`
  test "the sidebar shows a group an admin pins to everyone's sidebar while it's open" do
    account = fake_account!()
    me = fake_user!(account)
    admin = fake_admin!(fake_account!())

    group =
      Bonfire.Classify.Simulate.fake_group!(admin, %{
        name: "Pinned for everyone",
        membership: "open",
        visibility: "global",
        participation: "group_members"
      })

    session =
      conn(user: me, account: account)
      |> visit("/dashboard")
      |> refute_has("[data-role='sidebar-group']", text: "Pinned for everyone")

    {:ok, _} = Bonfire.Social.Pins.pin(admin, group, :instance)

    assert_has(session, "[data-role='sidebar-group']",
      text: "Pinned for everyone",
      timeout: 1_000
    )
  end

  test "a pinned sidebar topic opens in its group and retains the entry page" do
    account = fake_account!()
    me = fake_user!(account)
    group = Bonfire.Classify.Simulate.fake_group!(me)

    topic =
      Bonfire.Classify.Simulate.fake_category!(me, group, %{
        name: Bonfire.Common.Simulation.word(),
        type: :topic
      })

    {:ok, _} = Bonfire.Social.Pins.pin(me, group, nil, to_feeds: [])
    entry = "/feed?sort=latest"

    conn(user: me, account: account)
    |> visit(Bonfire.Classify.Web.GroupNavigation.link(Bonfire.Common.URIs.path(group), entry))
    |> assert_has("[data-role='sidebar-group'] details[open]", timeout: 1_000)
    |> click_link("[data-role='sidebar-topics'] a", topic.profile.name)
    |> assert_has("[data-role='sidebar-topics'] a[aria-current='page']",
      text: topic.profile.name,
      timeout: 1_000
    )
    |> assert_has("[data-id=group_topics] [data-role=group-topic-current]",
      text: topic.profile.name
    )
    # the chips patch within the group, so their hrefs carry no entry page: the view keeps it
    |> assert_has("#group-topic-all[href='#{Bonfire.Common.URIs.path(group)}']")
    |> refute_has("#group-topic-all[href*='group_from']")
    |> assert_has("a[href='/feed?sort=latest'][aria-label='Go back to the previous page']")
  end

  test "a feed entry survives the topic chips and the /+topic redirect" do
    account = fake_account!()
    me = fake_user!(account)
    group = Bonfire.Classify.Simulate.fake_group!(me)

    # a bare `Faker.Lorem.word()` can be "a", whose derived username is too short to be valid, so the insert failed now and then
    topic_name = "#{Faker.Lorem.word()} topic"
    topic = Bonfire.Classify.Simulate.fake_category!(me, group, %{name: topic_name, type: :topic})
    entry = "/feed?sort=latest"

    connection =
      conn(user: me, account: account)
      |> Phoenix.LiveViewTest.put_connect_params(%{
        "_live_referer" => "http://localhost:4000" <> entry
      })

    {:ok, view, _} = live(connection, "/group/#{group.character.username}")

    assert has_element?(
             view,
             "a[href='/feed?sort=latest'][aria-label='Go back to the previous page']"
           )

    assert has_element?(
             view,
             "#group-topic-link-#{topic.id}[href='#{Bonfire.Classify.Web.GroupNavigation.topic_path(group, topic)}']"
           )

    # `/+topic` redirects into the group, carrying the entry page, and All patches back to the group
    conn(user: me, account: account)
    |> visit(Bonfire.Classify.Web.GroupNavigation.link(Bonfire.Common.URIs.path(topic), entry))
    |> assert_path(Bonfire.Classify.Web.GroupNavigation.topic_path(group, topic))
    |> click_link("#group-topic-all", "All")
    |> assert_path(Bonfire.Common.URIs.path(group))
    |> assert_has("a[href='/feed?sort=latest'][aria-label='Go back to the previous page']")
  end

  test "a feed entry survives members and settings round trips" do
    account = fake_account!()
    me = fake_user!(account)
    group = Bonfire.Classify.Simulate.fake_group!(me)
    entry = "/feed?sort=latest"
    group_path = Bonfire.Common.URIs.path(group)

    for {tab, selector, label} <- [
          {"members", "[data-role='group-hero-members']", "member"},
          {"settings", "a[aria-label='Manage']", "Manage"}
        ] do
      {:ok, view, _} =
        conn(user: me, account: account)
        |> live(Bonfire.Classify.Web.GroupNavigation.link(group_path, entry))

      # the member count and the Manage gear patch within the group, so the view keeps the entry page and their hrefs are the plain paths
      assert has_element?(view, "a[href='#{group_path}/#{tab}']")

      session =
        conn(user: me, account: account)
        |> visit(Bonfire.Classify.Web.GroupNavigation.link(group_path, entry))

      session = click_link(session, selector, label)

      parent_selector =
        if tab == "members",
          do: "#members-parent-link",
          else: "a[aria-label='Go back to the previous page']"

      # the members page's group link and the settings' back button both patch, so both are the plain path: the view keeps the entry page
      # parent_href =
      #   if tab == "members",
      #     do: group_path,
      #     else: Bonfire.Classify.Web.GroupNavigation.link(group_path, entry)
      parent_href = group_path

      session
      |> assert_has("#{parent_selector}[href='#{parent_href}']")
      |> click_link(
        parent_selector,
        if(tab == "members", do: group.profile.name, else: "Go back to the previous page")
      )
      |> assert_has("a[href='/feed?sort=latest'][aria-label='Go back to the previous page']")
    end
  end

  describe "the entry page is kept by the group's view, not by its links" do
    @entry "/feed?sort=latest"
    @back "a[href='/feed?sort=latest'][aria-label='Go back to the previous page']"

    # the page header's back button on a group's own sub-pages: a patch to the group, with no entry page in its href
    defp back_to_group(ctx),
      do:
        "a[data-phx-link='patch'][href='#{ctx.group_path}'][aria-label='Go back to the previous page']"

    setup do
      account = fake_account!()
      me = fake_user!(account)
      group = Bonfire.Classify.Simulate.fake_group!(me)

      topic =
        Bonfire.Classify.Simulate.fake_category!(me, group, %{
          name: "#{Faker.Lorem.word()} topic",
          type: :topic
        })

      %{
        account: account,
        me: me,
        group: group,
        topic: topic,
        group_path: Bonfire.Common.URIs.path(group),
        topic_path: Bonfire.Classify.Web.GroupNavigation.topic_path(group, topic)
      }
    end

    defp connection_from_entry(ctx) do
      conn(user: ctx.me, account: ctx.account)
      |> Phoenix.LiveViewTest.put_connect_params(%{
        "_live_referer" => "http://localhost:4000" <> @entry
      })
    end

    test "the links inside the group are the plain paths", ctx do
      {:ok, view, _} = live(connection_from_entry(ctx), ctx.group_path)

      # positive first: the links are there and go to the right places
      assert has_element?(view, @back)
      assert has_element?(view, "#group-topic-all[href='#{ctx.group_path}']")
      assert has_element?(view, "#group-topic-link-#{ctx.topic.id}[href='#{ctx.topic_path}']")

      assert has_element?(
               view,
               "[data-role='group-hero-members'][href='#{ctx.group_path}/members']"
             )

      assert has_element?(view, "a[aria-label='Manage'][href='#{ctx.group_path}/settings']")

      refute has_element?(view, "[data-id=group_hero] a[href*='group_from']")
    end

    test "the topic chips patch and the back link still goes to the entry page", ctx do
      {:ok, view, _} = live(connection_from_entry(ctx), ctx.group_path)

      view |> element("#group-topic-link-#{ctx.topic.id}") |> render_click()
      assert_patch(view, ctx.topic_path)
      assert has_element?(view, @back)

      view |> element("#group-topic-all") |> render_click()
      assert_patch(view, ctx.group_path)
      assert has_element?(view, @back)
    end

    test "the member count patches to the members page and its group link patches back", ctx do
      {:ok, view, _} = live(connection_from_entry(ctx), ctx.group_path)

      view |> element("[data-role='group-hero-members']") |> render_click()
      assert_patch(view, "#{ctx.group_path}/members")
      assert has_element?(view, "#members-parent-link[href='#{ctx.group_path}']")

      view |> element("#members-parent-link") |> render_click()
      assert_patch(view, ctx.group_path)
      assert has_element?(view, @back)
    end

    test "the Manage gear patches to the settings", ctx do
      {:ok, view, _} = live(connection_from_entry(ctx), ctx.group_path)

      view |> element("a[aria-label='Manage']") |> render_click()
      assert_patch(view, "#{ctx.group_path}/settings")

      # the back button goes to the group, as a patch, so it is the plain path
      # assert has_element?(
      #          view,
      #          "a[aria-label='Go back to the previous page'][href='#{Bonfire.Classify.Web.GroupNavigation.link(ctx.group_path, @entry)}']"
      #        )
      assert has_element?(view, back_to_group(ctx))

      refute has_element?(
               view,
               "a[aria-label='Go back to the previous page'][href*='group_from']"
             )
    end

    test "the settings' back button patches to the group and the group's back is still the entry page",
         ctx do
      {:ok, view, _} = live(connection_from_entry(ctx), "#{ctx.group_path}/settings")

      # positive first: the button is there, pointing at the group, with no entry page in its href
      assert has_element?(view, back_to_group(ctx))

      refute has_element?(
               view,
               "a[aria-label='Go back to the previous page'][href*='group_from']"
             )

      view |> element(back_to_group(ctx)) |> render_click()
      assert_patch(view, ctx.group_path)
      assert has_element?(view, @back)
    end

    # the members page draws no page header (its own header carries the group link), so the group link is the way back from it
    test "the members page, opened directly, patches back to the group and the group's back is still the entry page",
         ctx do
      {:ok, view, _} = live(connection_from_entry(ctx), "#{ctx.group_path}/members")

      # positive first: the link is there, pointing at the group, with no entry page in any href of the page's own header
      assert has_element?(view, "#members-parent-link[href='#{ctx.group_path}']")
      refute has_element?(view, "#group-member-directory a[href*='group_from']")

      view |> element("#members-parent-link") |> render_click()
      assert_patch(view, ctx.group_path)
      assert has_element?(view, @back)
    end

    test "a standalone topic's link to its group still returns to the entry page", ctx do
      connection = connection_from_entry(ctx)
      {:ok, view, _} = live(connection, "/topic/#{ctx.topic.id}/followers")

      assert has_element?(
               view,
               "#topic-parent-link[href='#{Bonfire.Classify.Web.GroupNavigation.link(ctx.group_path, @entry)}']"
             )

      {:ok, group_view, _} =
        view
        |> element("#topic-parent-link")
        |> render_click()
        |> follow_redirect(connection)

      assert has_element?(group_view, @back)
    end
  end

  # The sidebar's rows are in `PersistentLive`, a sticky child view. LiveViewTest sends a click on a patch link to the view the link sits in, where the browser sends it to the main view (`pushLinkPatch`), so each test checks the row (a patch link with the plain path) and then patches the main view with its href, as the client does.
  describe "the sidebar's rows patch and keep the group's state" do
    # `@entry` and `@back` are the previous describe's
    @group_main "[data-id=group]"

    setup do
      Process.put(:federating, false)
      Process.put([:bonfire, :feed_live_update_many_preload_mode], :inline)

      account = fake_account!()
      me = fake_user!(account)
      other = fake_user!()

      # `me` created and runs this one
      alpha =
        Bonfire.Classify.Simulate.fake_group!(me, %{
          name: "Alpha club",
          membership: "open",
          visibility: "global",
          participation: "anyone",
          default_content_visibility: "public"
        })

      alpha_topic =
        Bonfire.Classify.Simulate.fake_category!(me, alpha, %{name: "Alpha topic", type: :topic})

      Bonfire.Classify.Simulate.fake_post_in_group!(me, alpha, "<p>Alpha discussion</p>")

      # `me` has not joined this one, which has another member
      beta =
        Bonfire.Classify.Simulate.fake_group!(other, %{
          name: "Beta club",
          membership: "open",
          visibility: "global",
          participation: "anyone",
          default_content_visibility: "public"
        })

      beta_topic =
        Bonfire.Classify.Simulate.fake_category!(other, beta, %{name: "Beta topic", type: :topic})

      Bonfire.Classify.Simulate.fake_post_in_group!(other, beta, "<p>Beta discussion</p>")
      {:ok, _} = Bonfire.Classify.Categories.join_and_follow_group(fake_user!(), beta)

      {:ok, _} = Bonfire.Social.Pins.pin(me, alpha, nil, to_feeds: [])
      {:ok, _} = Bonfire.Social.Pins.pin(me, beta, nil, to_feeds: [])

      %{
        account: account,
        me: me,
        alpha: alpha,
        beta: beta,
        alpha_path: Bonfire.Common.URIs.path(alpha),
        beta_path: Bonfire.Common.URIs.path(beta),
        alpha_topic_path: Bonfire.Classify.Web.GroupNavigation.topic_path(alpha, alpha_topic)
      }
    end

    defp entered_from(ctx, entry) do
      conn(user: ctx.me, account: ctx.account)
      |> Phoenix.LiveViewTest.put_connect_params(%{
        "_live_referer" => "http://localhost:4000" <> entry
      })
    end

    # the sidebar loads its groups once connected: waits for the row to the path (positive first), then asks that it is a patch link whose href is the plain path
    defp sidebar_row(view, scope, path) do
      row_to_path = "#{scope} a[href^='#{path}']"

      Enum.find_value(1..20, fn _ ->
        if has_element?(view, row_to_path) do
          true
        else
          Process.sleep(100)
          nil
        end
      end)

      assert has_element?(view, row_to_path), "the sidebar has no row to #{path}"

      assert has_element?(view, "#{scope} a[data-phx-link='patch'][href='#{path}']"),
             "the sidebar's row to #{path} is not a patch link with that plain path"
    end

    test "a topic row patches inside the group, and the group's back is still the entry page",
         ctx do
      {:ok, view, _} = live(entered_from(ctx, @entry), ctx.alpha_path)
      assert has_element?(view, @back)

      sidebar_row(view, "[data-role=sidebar-topics]", ctx.alpha_topic_path)
      refute has_element?(view, "[data-role=sidebar-groups] a[href*='group_from']")

      render_patch(view, ctx.alpha_topic_path)
      assert_patch(view, ctx.alpha_topic_path)

      assert has_element?(view, @back)

      assert has_element?(
               view,
               "[data-id=group_topics] [data-role=group-topic-current]",
               "Alpha topic"
             )
    end

    test "a group row patches to the other group, which shows nothing of the first", ctx do
      {:ok, view, _} = live(entered_from(ctx, @entry), ctx.alpha_path)

      # positive first: the first group is all there is, and the other's row is a patch link to its plain path
      live_async_wait(view)
      assert has_element?(view, "[data-id=group_hero]", "Alpha club")
      assert has_element?(view, "[data-id=group_topics]", "Alpha topic")
      assert has_element?(view, "[data-role=group-hero-members]", "1 member")
      assert has_element?(view, "a[aria-label='Manage'][href='#{ctx.alpha_path}/settings']")
      assert has_element?(view, "[data-id=feed]", "Alpha discussion")
      refute has_element?(view, "#join_btn_#{id(ctx.alpha)}")

      sidebar_row(view, "[data-role=sidebar-groups]", ctx.beta_path)

      render_patch(view, ctx.beta_path)
      assert_patch(view, ctx.beta_path)
      live_async_wait(view)

      # the other group, with its own name, topics, members, join state, and feed
      assert has_element?(view, "[data-id=group_hero]", "Beta club")
      assert has_element?(view, "[data-id=group_topics]", "Beta topic")
      assert has_element?(view, "[data-role=group-hero-members]", "2 members")
      assert has_element?(view, "#join_btn_#{id(ctx.beta)}")
      assert has_element?(view, "[data-id=feed]", "Beta discussion")

      # and none of the first's
      refute has_element?(view, @group_main, "Alpha club")
      refute has_element?(view, @group_main, "Alpha topic")
      refute has_element?(view, "[data-role=group-hero-members]", "1 member")
      refute has_element?(view, "a[aria-label='Manage']")
      refute has_element?(view, "#join_btn_#{id(ctx.alpha)}")
      refute has_element?(view, "[data-id=feed]", "Alpha discussion")

      # the entry page is still where back goes
      assert has_element?(view, @back)

      # and back to the first, which is again what it was
      render_patch(view, ctx.alpha_path)
      assert_patch(view, ctx.alpha_path)
      live_async_wait(view)

      assert has_element?(view, "[data-id=group_hero]", "Alpha club")
      assert has_element?(view, "[data-role=group-hero-members]", "1 member")
      assert has_element?(view, "a[aria-label='Manage'][href='#{ctx.alpha_path}/settings']")
      assert has_element?(view, "[data-id=feed]", "Alpha discussion")
      refute has_element?(view, "[data-id=feed]", "Beta discussion")
      refute has_element?(view, "#join_btn_#{id(ctx.beta)}")
      assert has_element?(view, @back)
    end

    # the members page's search and role filter are the view's own state, not a group's: the other group's page starts with none
    test "a group row patches to the other group, whose members page starts without the first's search and filter",
         ctx do
      {:ok, view, _} = live(entered_from(ctx, @entry), ctx.alpha_path)

      render_patch(view, "#{ctx.alpha_path}/members")
      assert_patch(view, "#{ctx.alpha_path}/members")

      # positive first: the filters work on the first group's page
      view |> element("#members-filter-moderators") |> render_click()
      render_click(view, "Bonfire.UI.Groups:filter_members", %{"members" => %{"search" => "zzz"}})
      assert has_element?(view, "#members-filter-moderators[aria-pressed='true']")
      assert has_element?(view, "#member-search[value='zzz']")

      sidebar_row(view, "[data-role=sidebar-groups]", ctx.beta_path)
      render_patch(view, ctx.beta_path)
      assert_patch(view, ctx.beta_path)

      render_patch(view, "#{ctx.beta_path}/members")
      assert_patch(view, "#{ctx.beta_path}/members")

      assert has_element?(view, "#members-filter-all[aria-pressed='true']")
      assert has_element?(view, "#members-filter-moderators[aria-pressed='false']")
      refute has_element?(view, "#member-search[value='zzz']")
    end

    test "a group row patches to a group that only shows a preview, and the first group's feed and composer give way to its gate",
         ctx do
      gamma =
        Bonfire.Classify.Simulate.fake_group!(fake_user!(), %{
          name: "Gamma preview",
          membership: "on_request",
          visibility: "nonfederated:preview",
          participation: "group_members",
          default_content_visibility: "members:private"
        })

      {:ok, _} = Bonfire.Social.Pins.pin(ctx.me, gamma, nil, to_feeds: [])
      gamma_path = Bonfire.Common.URIs.path(gamma)

      {:ok, view, _} = live(entered_from(ctx, @entry), ctx.alpha_path)
      live_async_wait(view)

      # positive first: the first group shows its feed and composer, and no gate
      assert has_element?(view, "[data-id=feed]", "Alpha discussion")
      assert has_element?(view, "#inline_composer_placeholder")
      refute has_element?(view, "#group_access_gate")

      sidebar_row(view, "[data-role=sidebar-groups]", gamma_path)

      render_patch(view, gamma_path)
      assert_patch(view, gamma_path)
      live_async_wait(view)

      assert has_element?(view, "[data-id=group_hero]", "Gamma preview")
      assert has_element?(view, "#group_access_gate")
      refute has_element?(view, "[data-id=feed]")
      refute has_element?(view, "#inline_composer_placeholder")
      refute has_element?(view, "a[aria-label='Manage']")

      # and back to the first, whose gate is gone
      render_patch(view, ctx.alpha_path)
      assert_patch(view, ctx.alpha_path)
      live_async_wait(view)

      refute has_element?(view, "#group_access_gate")
      assert has_element?(view, "[data-id=feed]", "Alpha discussion")
      assert has_element?(view, "#inline_composer_placeholder")
    end

    test "a group row patches from a page that is not a group, which the server answers with a navigate, and the group's back is that page",
         ctx do
      {:ok, view, _} = live(entered_from(ctx, "/"), "/feed")

      sidebar_row(view, "[data-role=sidebar-groups]", ctx.beta_path)

      # the feed's view doesn't serve the group's route: it stays, and answers the client with `link_redirect`
      render_patch(view, ctx.beta_path)
      assert Process.alive?(view.pid)
      assert has_element?(view, "[data-id=feed]")

      # and the client mounts the group's view, with the page it left as `_live_referer`
      {:ok, group_view, _} = live(entered_from(ctx, "/feed"), ctx.beta_path)

      assert has_element?(group_view, "[data-id=group_hero]", "Beta club")

      assert has_element?(
               group_view,
               "a[href='/feed'][aria-label='Go back to the previous page']"
             )
    end
  end
end
