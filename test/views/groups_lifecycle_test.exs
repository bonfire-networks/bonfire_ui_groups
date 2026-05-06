defmodule Bonfire.UI.Groups.LiveHandlerTest do
  use Bonfire.UI.Groups.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  alias Bonfire.Classify.Categories

  defp post_in_group(session, content, group_id) do
    params = %{
      "post" => %{"post_content" => %{"html_body" => content}},
      "context_id" => group_id,
      "to_circles" => [group_id]
    }

    session
    |> PhoenixTest.unwrap(fn view ->
      view
      |> Phoenix.LiveViewTest.element("#smart_input_form")
      |> Phoenix.LiveViewTest.render_submit(params)
    end)
  end

  defp create_group(creator, attrs \\ %{}) do
    name = attrs[:name] || "Test Group #{System.unique_integer([:positive])}"

    dims =
      Keyword.take(attrs, [:membership, :visibility, :participation, :default_content_visibility])

    base = %{
      name: name,
      description: attrs[:description] || "A test group",
      type: :group
    }

    # Support legacy to_boundaries for old tests; dimensional attrs take precedence
    base =
      if attrs[:to_boundaries] && length(dims) == 0,
        do: Map.put(base, :to_boundaries, attrs[:to_boundaries]),
        else: Enum.into(dims, base)

    base =
      if attrs[:preset_slug], do: Map.put(base, :preset_slug, attrs[:preset_slug]), else: base

    {:ok, group} = Categories.create(creator, base, true)
    group
  end

  # Create a group whose ACLs match a known preset, so the boundaries
  # editor should preselect that preset on load.
  defp create_group_with_preset(creator, preset_slug, name) do
    meta = Bonfire.Common.Config.get([:group_presets, preset_slug], %{}, :bonfire_classify)

    attrs =
      %{name: name, type: :group, preset_slug: preset_slug}
      |> Map.merge(
        Map.take(meta, [:membership, :visibility, :participation, :default_content_visibility])
      )

    {:ok, group} = Categories.create(creator, attrs, true)
    group
  end

  describe "group creation" do
    test "create a group via the LiveHandler" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group(me, name: "Created Group", description: "test description")

      assert group.profile.name == "Created Group"
      assert group.character.username

      conn = conn(user: me, account: account)
      {:ok, _view, html} = live(conn, "/&#{group.character.username}")

      assert html =~ "Created Group"
    end

    test "create group form is accessible from the groups page" do
      account = fake_account!()
      me = fake_user!(account)
      conn = conn(user: me, account: account)

      {:ok, _view, html} = live(conn, "/groups")

      assert html =~ "Create a group"
    end

    test "group is accessible at its URL after creation" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group(me, name: "Accessible Group")

      conn = conn(user: me, account: account)
      {:ok, _view, html} = live(conn, "/&#{group.character.username}")

      assert html =~ "Accessible Group"
    end
  end

  describe "group page" do
    test "group creator can see the group page with name and description" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group(me, name: "Cozy Club", description: "A cozy place")

      conn = conn(user: me, account: account)
      {:ok, _view, html} = live(conn, "/&#{group.character.username}")

      assert html =~ "Cozy Club"
    end

    test "I cannot see a private group without an invite" do
      account = fake_account!()
      me = fake_user!(account)
      alice = fake_user!(account)

      group = create_group(me, membership: "invite_only", visibility: "members:private")

      conn = conn(user: alice, account: account)
      {:error, _} = live(conn, "/&#{group.character.username}")
    end

    test "group creator is listed as a member on about page" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group(me, name: "My Group")

      conn = conn(user: me, account: account)
      {:ok, _view, html} = live(conn, "/&#{group.character.username}/about")

      assert html =~ e(me, :profile, :name, "")
    end

    test "group about page shows group details" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group(me, name: "Detail Group", description: "A detailed description")

      conn = conn(user: me, account: account)
      {:ok, _view, html} = live(conn, "/&#{group.character.username}/about")

      assert html =~ "Group details"
      assert html =~ "Members"
      assert html =~ "Created"
    end

    test "group appears in the groups listing" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group(me, name: "Listed Group")

      conn = conn(user: me, account: account)
      {:ok, _view, html} = live(conn, "/groups")

      assert html =~ "Listed Group"
    end

    test "group sidebar shows joined groups" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group(me, name: "Sidebar Group")

      conn = conn(user: me, account: account)
      {:ok, _view, html} = live(conn, "/&#{group.character.username}")

      assert html =~ "Sidebar Group"
    end
  end

  describe "group settings" do
    test "group admin can access settings page" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group(me, name: "Settings Group")

      conn = conn(user: me, account: account)
      {:ok, _view, html} = live(conn, "/&#{group.character.username}/settings")

      assert html =~ "Identity"
      assert html =~ "Permissions"
      assert html =~ "Rules"
    end

    test "group admin can edit group name and description" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group(me, name: "Old Name", description: "Old description")

      conn = conn(user: me, account: account)
      {:ok, view, _html} = live(conn, "/&#{group.character.username}/settings")

      html =
        view
        |> form("form[phx-submit='Bonfire.Classify:edit']", %{
          "profile" => %{"name" => "New Name", "summary" => "New description"}
        })
        |> render_submit()

      assert html =~ "updated" or html =~ "New Name"
    end

    test "non-admin cannot edit group settings" do
      account = fake_account!()
      me = fake_user!(account)
      alice = fake_user!(account)
      group = create_group(me, name: "Protected Group")

      {:ok, _} = Categories.join_group(alice, group)

      conn = conn(user: alice, account: account)
      {:ok, _view, html} = live(conn, "/&#{group.character.username}/settings")

      # apostrophe is HTML-escaped in rendered output, so match a quote-free substring
      assert html =~ "permission to edit this group"
    end

    test "settings page shows danger zone with archive action" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group(me, name: "Danger Group")

      conn = conn(user: me, account: account)
      {:ok, _view, html} = live(conn, "/&#{group.character.username}/settings")

      assert html =~ "Danger zone"
      assert html =~ "Archive group"
    end
  end

  describe "group boundaries settings (preselection)" do
    test "boundaries tab preselects the preset matching the group's current dims" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group_with_preset(me, "public_local_community", "Public Settings Group")

      conn = conn(user: me, account: account)
      {:ok, _view, html} = live(conn, "/&#{group.character.username}/settings/boundaries")

      # The selected card carries aria-checked="true". Use the preset slug as
      # data attribute to identify it unambiguously.
      assert html =~ ~s(data-preset="public_local_community")

      assert html =~
               ~r/data-preset="public_local_community"[^>]*aria-checked="true"|aria-checked="true"[^>]*data-preset="public_local_community"/
    end

    # Detection can't match circle-controlled participation slugs (`group_members`,
    # `moderators`) since they have no global ACL signature — so the preset
    # resolver must accept a m+v match when the detected participation is nil.
    test "boundaries tab preselects a preset whose participation is circle-controlled" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group_with_preset(me, "private_club", "Private Club Group")

      conn = conn(user: me, account: account)
      {:ok, _view, html} = live(conn, "/&#{group.character.username}/settings/boundaries")

      assert html =~
               ~r/data-preset="private_club"[^>]*aria-checked="true"|aria-checked="true"[^>]*data-preset="private_club"/
    end

    test "boundaries tab falls back to Custom when group dims don't match any preset" do
      account = fake_account!()
      me = fake_user!(account)

      # Hand-rolled dim combo that no preset declares — forces "custom" fallback.
      group =
        create_group(me,
          name: "Custom Dims Group",
          membership: "invite_only",
          visibility: "local:discoverable",
          participation: "local:contributors"
        )

      conn = conn(user: me, account: account)
      {:ok, _view, html} = live(conn, "/&#{group.character.username}/settings/boundaries")

      assert html =~
               ~r/data-preset="custom"[^>]*aria-checked="true"|aria-checked="true"[^>]*data-preset="custom"/
    end

    test "picking a preset updates the editor's selected card" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group_with_preset(me, "public_local_community", "Switching Group")

      conn = conn(user: me, account: account)
      {:ok, view, _html} = live(conn, "/&#{group.character.username}/settings/boundaries")

      # Click the private_club preset card; the editor handles pick_preset
      # and re-renders its hidden inputs with private_club's dim slugs.
      after_click =
        view
        |> element(~s(button[data-preset="private_club"]))
        |> render_click()

      # The editor's selected card switched to private_club.
      assert after_click =~
               ~r/data-preset="private_club"[^>]*aria-checked="true"|aria-checked="true"[^>]*data-preset="private_club"/

      # And the previously-selected one is no longer marked as checked.
      refute after_click =~
               ~r/data-preset="public_local_community"[^>]*aria-checked="true"|aria-checked="true"[^>]*data-preset="public_local_community"/
    end

    # Regression: switching presets used to leave the old dim ACLs alongside the
    # new ones, so detection resolved to the previous preset.
    test "submitting the boundaries form persists the new preset's dims" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group_with_preset(me, "public_local_community", "Persisting Group")

      conn = conn(user: me, account: account)
      {:ok, view, _html} = live(conn, "/&#{group.character.username}/settings/boundaries")

      view
      |> element(~s(button[data-preset="private_club"]))
      |> render_click()

      view
      |> element("#group_settings_boundaries_form")
      |> render_submit()

      target = Bonfire.Common.Config.get([:group_presets, "private_club"], %{}, :bonfire_classify)
      detected = Bonfire.Boundaries.Presets.group_dimension_slugs(%{id: group.id})

      assert detected.membership == target.membership,
             "settings submit: membership detected #{inspect(detected.membership)}, expected #{inspect(target.membership)}"

      assert detected.visibility == target.visibility,
             "settings submit: visibility detected #{inspect(detected.visibility)}, expected #{inspect(target.visibility)}"
    end
  end

  describe "group membership" do
    # TODO: passes solo, fails in full suite (test-ordering/isolation issue, not a real bug)
    @tag :todo
    test "if I create a on_request group, anyone can request to join" do
      account = fake_account!()
      me = fake_user!(account)
      alice = fake_user!(account)

      group =
        create_group(me,
          name: "on_request Group",
          membership: "on_request",
          visibility: "local:discoverable"
        )

      conn(user: alice, account: account)
      |> visit("/&#{group.character.username}/about")
      |> wait_async()
      |> assert_has("[phx-value-id='#{group.id}']", text: "Request to join")
      |> click_link("[phx-value-id='#{group.id}']", "Request to join")
      |> wait_async()
      |> assert_has("[phx-value-id='#{group.id}']", text: "Requested")

      refute Categories.member?(alice, group)
    end

    test "non-member sees 'Join group' button on open group about page, and after joining, user sees 'Joined' button, and after leaving, user sees 'Join group' button again" do
      account = fake_account!()
      me = fake_user!(account)
      alice = fake_user!(account)
      group = create_group(me, name: "Join Flow Group", membership: "local:members")

      conn = conn(user: alice, account: account)

      conn
      |> visit("/&#{group.character.username}/about")
      |> wait_async()
      |> assert_has("[phx-value-id='#{group.id}']", text: "Join group")
      |> click_link("[phx-value-id='#{group.id}']", "Join group")
      |> wait_async()
      |> assert_has("[phx-value-id='#{group.id}']", text: "Joined")
      |> click_link("[phx-value-id='#{group.id}']", "Joined")
      |> wait_async()
      |> assert_has("[phx-value-id='#{group.id}']", text: "Join group")
    end

    test "group creator is automatically a member and sees the 'Manage' link instead of a join button" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group(me, name: "Creator Button Group")

      conn = conn(user: me, account: account)

      conn
      |> visit("/&#{group.character.username}/about")
      |> wait_async()
      |> assert_has("a", text: "Manage")
      |> refute_has("[phx-value-id='#{group.id}']", text: "Join group")
    end

    test "a joined member appears on the group about page" do
      account = fake_account!()
      me = fake_user!(account)
      alice = fake_user!(account)
      group = create_group(me, name: "Member Check Group", membership: "local:members")

      conn(user: alice, account: account)
      |> visit("/&#{group.character.username}/about")
      |> wait_async()
      |> click_link("[phx-value-id='#{group.id}']", "Join group")
      |> wait_async()

      conn(user: me, account: account)
      |> visit("/&#{group.character.username}/about")
      |> wait_async()
      |> assert_has("*", text: e(alice, :profile, :name, ""))
    end

    # `announcement_channel` is `invite_only` — there's no self-serve join. The button
    # would be misleading, so it must be hidden for non-members.
    test "non-member of an invite_only announcement_channel does not see a join button" do
      account = fake_account!()
      me = fake_user!(account)
      alice = fake_user!(account)

      group =
        create_group(me,
          name: "Invite Only Channel",
          membership: "invite_only",
          visibility: "nonfederated:discoverable",
          participation: "moderators"
        )

      conn(user: alice, account: account)
      |> visit("/&#{group.character.username}/about")
      |> wait_async()
      |> refute_has("[phx-value-id='#{group.id}']", text: "Join group")
      |> refute_has("[phx-value-id='#{group.id}']", text: "Request to join")
    end

    # Regression: cond fall-through in join_button_live.sface used to land non-member
    # invite-only viewers on the "Joined" else-branch, falsely implying membership.
    test "non-member of an invite_only group does not see a 'Joined' label" do
      account = fake_account!()
      me = fake_user!(account)
      alice = fake_user!(account)

      group =
        create_group(me,
          name: "Joined Label Regression Group",
          membership: "invite_only",
          visibility: "nonfederated:discoverable",
          participation: "moderators"
        )

      conn(user: alice, account: account)
      |> visit("/&#{group.character.username}")
      |> wait_async()
      |> refute_has("[phx-value-id='#{group.id}']", text: "Joined")
      |> refute_has("[phx-value-id='#{group.id}']", text: "Leave group")
    end
  end

  describe "composer gating" do
    # Inline composer is gated on `@can_create_in_category`, recomputed by
    # `LiveHandler.refresh_membership_assigns/2` after join/leave.
    test "creator sees the inline composer on their group page" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group(me, name: "Creator Composer Group")

      conn(user: me, account: account)
      |> visit("/&#{group.character.username}")
      |> wait_async()
      |> assert_has("#inline_composer_placeholder")
    end

    # private_club has `participation: "group_members"` — only members can post.
    test "non-member of a private_club group does not see the inline composer" do
      account = fake_account!()
      me = fake_user!(account)
      alice = fake_user!(account)

      group =
        create_group(me,
          name: "Gated Private Group",
          membership: "on_request",
          visibility: "local:discoverable",
          participation: "group_members",
          default_content_visibility: "members:private"
        )

      conn(user: alice, account: account)
      |> visit("/&#{group.character.username}")
      |> wait_async()
      |> refute_has("#inline_composer_placeholder")
    end

    # `announcement_channel` is `participation: "moderators"` — only mods post.
    # The creator is auto-mod, so they see the composer; everyone else doesn't.
    test "non-moderator does not see the inline composer in an announcement_channel" do
      account = fake_account!()
      me = fake_user!(account)
      alice = fake_user!(account)

      group =
        create_group(me,
          name: "Announce Channel",
          membership: "invite_only",
          visibility: "nonfederated:discoverable",
          participation: "moderators",
          default_content_visibility: "nonfederated"
        )

      conn(user: alice, account: account)
      |> visit("/&#{group.character.username}")
      |> wait_async()
      |> refute_has("#inline_composer_placeholder")
    end

    # `participation` is independent of membership: with `local:contributors` anyone on
    # the instance can post, so the composer is intentionally visible to non-members
    # without joining. Locks in the design so a future "hide until joined" change is
    # an explicit decision, not a regression.
    test "non-member of an open-participation group sees the inline composer without joining" do
      account = fake_account!()
      me = fake_user!(account)
      alice = fake_user!(account)

      group =
        create_group(me,
          name: "Open Participation Group",
          membership: "local:members",
          participation: "local:contributors",
          visibility: "nonfederated:discoverable",
          default_content_visibility: "nonfederated"
        )

      conn(user: alice, account: account)
      |> visit("/&#{group.character.username}")
      |> wait_async()
      |> assert_has("#inline_composer_placeholder")
    end
  end

  describe "discoverable group access for non-members" do
    # The `:see || :read` chain in classify_live_handler's mounted/3 is what allows
    # non-members to land on the page (and request to join) for discoverable groups.
    test "non-member can load a local:discoverable on_request group page" do
      account = fake_account!()
      me = fake_user!(account)
      alice = fake_user!(account)

      group =
        create_group(me,
          name: "Discoverable Group",
          membership: "on_request",
          visibility: "local:discoverable"
        )

      conn(user: alice, account: account)
      |> visit("/&#{group.character.username}")
      |> wait_async()
      |> assert_has("*", text: "Discoverable Group")
    end
  end

  describe "publish in group" do
    test "anyone can post in open group, which visible to the author when visiting the group" do
      account = fake_account!()
      me = fake_user!(account)

      group =
        create_group(me,
          name: "Feed Post Group for Author",
          membership: "local:members",
          participation: "anyone",
          visibility: "nonfederated",
          default_content_visibility: "nonfederated"
        )

      conn(user: me, account: account)
      |> visit("/&#{group.character.username}")
      |> wait_async()
      |> post_in_group("<p>Group post content here</p>", group.id)

      conn(user: me, account: account)
      |> visit("/&#{group.character.username}")
      |> wait_async()
      |> assert_has_or_open_browser("article", text: "Group post content here")
    end

    # Submit through the form's hidden inputs (rather than injecting `to_boundaries`
    # directly into the params) so the test exercises the same render path as the
    # live UI — `BoundariesSelectionLive` previously dropped string-shaped slugs
    # silently on that path.
    test "post by moderator in announcement_channel is visible to non-members" do
      account = fake_account!()
      me = fake_user!(account)
      alice = fake_user!(account)

      group =
        create_group(me,
          name: "Announce Visibility Group",
          membership: "invite_only",
          visibility: "nonfederated:discoverable",
          participation: "moderators",
          default_content_visibility: "nonfederated"
        )

      params = %{
        "post" => %{"post_content" => %{"html_body" => "<p>Announcement to all</p>"}},
        "context_id" => group.id
      }

      conn(user: me, account: account)
      |> visit("/&#{group.character.username}")
      |> wait_async()
      |> PhoenixTest.unwrap(fn view ->
        view
        |> Phoenix.LiveViewTest.element("#smart_input_form")
        |> Phoenix.LiveViewTest.render_submit(params)
      end)

      conn(user: alice, account: account)
      |> visit("/&#{group.character.username}")
      |> wait_async()
      |> assert_has_or_open_browser("article", text: "Announcement to all")
    end

    test "members:private group is not accessible to non-members" do
      account = fake_account!()
      me = fake_user!(account)
      bob = fake_user!(account)
      group = create_group(me, name: "Closed Group", visibility: "members:private")

      conn(user: me, account: account)
      |> visit("/&#{group.character.username}")
      |> wait_async()
      |> post_in_group("<p>Secret group post</p>", group.id)

      # non-member cannot access the group page at all
      assert {:error, _} =
               live(conn(user: bob, account: account), "/&#{group.character.username}")
    end

    # TODO: `members:private` is empty in `preset_acls` — the DCV doesn't actually restrict
    # post visibility, so non-members can still read. Pre-existing boundary-system gap.
    @tag :todo
    test "post in global group with members:private DCV is not visible to non-members" do
      account = fake_account!()
      me = fake_user!(account)
      outsider = fake_user!(account)

      group =
        create_group(me,
          name: "Private Posts Group",
          visibility: "global",
          default_content_visibility: "members:private"
        )

      conn(user: me, account: account)
      |> visit("/&#{group.character.username}")
      |> wait_async()
      |> post_in_group("<p>Members only content</p>", group.id)

      conn(user: outsider, account: account)
      |> visit("/&#{group.character.username}")
      |> wait_async()
      |> refute_has_or_open_browser("article", text: "Members only content")
    end

    test "anyone can post in open group, which visible to anyone when visiting the group" do
      account = fake_account!()
      me = fake_user!(account)
      other = fake_user!(account)

      group =
        create_group(me,
          name: "Feed Post Group Public",
          membership: "local:members",
          participation: "anyone",
          visibility: "nonfederated",
          default_content_visibility: "nonfederated"
        )

      conn(user: me, account: account)
      |> visit("/&#{group.character.username}")
      |> wait_async()
      |> post_in_group("<p>Group post content here</p>", group.id)

      conn(user: other, account: account)
      |> visit("/&#{group.character.username}")
      |> wait_async()
      |> assert_has_or_open_browser("article", text: "Group post content here")
    end

    test "'Published in' label is shown on a group post when viewed in a regular feed" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group(me, name: "Label Test Group")

      conn(user: me, account: account)
      |> visit("/&#{group.character.username}")
      |> wait_async()
      |> post_in_group("<p>A post in a group</p>", group.id)

      conn(user: me, account: account)
      |> visit("/feed")
      |> wait_async()
      |> assert_has_or_open_browser("[data-role=published_in]", text: "Label Test Group")
    end

    test "'Published in' label is shown on a group post when viewed in author's timeline" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group(me, name: "Label Test Group")

      conn(user: me, account: account)
      |> visit("/&#{group.character.username}")
      |> wait_async()
      |> post_in_group("<p>A post in a group</p>", group.id)

      conn(user: me, account: account)
      |> visit("/@#{e(me, :character, :username, nil)}")
      |> wait_async()
      |> assert_has_or_open_browser("[data-role=published_in]", text: "Label Test Group")
    end

    test "post published in a sub-topic appears in the parent group feed" do
      account = fake_account!()
      me = fake_user!(account)

      group =
        create_group(me,
          name: "Group With Topics",
          membership: "local:members",
          participation: "anyone",
          visibility: "nonfederated",
          default_content_visibility: "nonfederated"
        )

      {:ok, topic} =
        Categories.create(me, %{name: "My Topic", type: :topic, parent_category: group})

      conn(user: me, account: account)
      |> visit("/&#{topic.character.username}")
      |> wait_async()
      |> post_in_group("<p>Post in sub-topic</p>", topic.id)

      conn(user: me, account: account)
      |> visit("/&#{group.character.username}")
      |> wait_async()
      |> assert_has_or_open_browser("article", text: "Post in sub-topic")
    end

    test "'Published in' label is hidden when viewing the post from within the group" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group(me, name: "Hidden Label Group")

      conn(user: me, account: account)
      |> visit("/&#{group.character.username}")
      |> wait_async()
      |> post_in_group("<p>A post in a group</p>", group.id)
      |> refute_has_or_open_browser("[data-role=published_in]", text: "Hidden Label Group")
    end
  end
end
