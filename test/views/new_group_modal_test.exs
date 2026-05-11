defmodule Bonfire.UI.Groups.NewGroupModalTest do
  @moduledoc """
  End-to-end coverage for the new-group creation modal
  (`Bonfire.UI.Groups.NewGroupLive` + `NewGroupFormLive`).

  These exercise the *UI* path — opening the modal, picking presets, toggling
  Layer-2 and Advanced, submitting — rather than the backend `Categories.create/3`
  path covered by `groups_lifecycle_test.exs`. They're regression guards for:

    * the `OpenModalLive` → `ReusableModalLive` stateful-child pattern
      (inline state in the outer component froze the modal snapshot; this test
      would have caught it)
    * name/description input race where typing in one cleared the other
    * the three-layer progressive disclosure surface (Layer 1 presets / Layer 2
      aggregated toggles / Layer 3 Advanced matrix)
    * the preset → boundary-dimension mapping at the config level
  """

  use Bonfire.UI.Groups.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  import Ecto.Query
  alias Bonfire.UI.Groups.NewGroupFormLive
  alias Bonfire.UI.Groups.GroupBoundaryEditorLive
  alias Bonfire.Classify.Category
  alias Bonfire.Common.Repo

  defp group_with_name_exists?(name) do
    from(c in Category, join: p in assoc(c, :profile), where: p.name == ^name, limit: 1)
    |> Repo.exists?()
  end

  defp submit_new_group_form(session, attrs) do
    session
    |> unwrap(fn view ->
      view
      |> Phoenix.LiveViewTest.element("#new_group_form")
      |> Phoenix.LiveViewTest.render_submit(attrs)
    end)
  end

  defp click_layer2_toggle(session, key) when is_binary(key) do
    session
    |> unwrap(fn view ->
      view
      |> Phoenix.LiveViewTest.element(
        ~s(input[phx-click="toggle_layer2"][phx-value-key="#{key}"])
      )
      |> Phoenix.LiveViewTest.render_click()
    end)
  end

  setup do
    account = fake_account!()
    me = fake_user!(account)
    conn = conn(user: me, account: account)
    {:ok, conn: conn, account: account, me: me}
  end

  describe "rendering" do
    test "the trigger button is present on the explore page", %{conn: conn} do
      conn
      |> visit("/groups")
      |> assert_has("[data-role=open_modal]")
    end

    test "opening the modal renders all configured preset cards + Custom", %{conn: conn} do
      conn
      |> visit("/groups")
      |> click_button("[data-role=open_modal]", "Create a group")
      |> assert_has("[data-preset=public_local_community]", text: "Public local community")
      |> assert_has("[data-preset=announcement_channel]", text: "Announcement channel")
      |> assert_has("[data-preset=private_club]", text: "Private club")
      |> assert_has("[data-preset=custom]", text: "Custom")
    end

    test "modal shows the intent-framing copy and the name field", %{conn: conn} do
      conn
      |> visit("/groups")
      |> click_button("[data-role=open_modal]", "Create a group")
      |> assert_has("p", text: "A space for people to gather around something")
      |> assert_has("#new_group_name")
    end

    test "Layer 2 hidden initially; Advanced region present but collapsed", %{conn: conn} do
      conn
      |> visit("/groups")
      |> click_button("[data-role=open_modal]", "Create a group")
      |> refute_has("h3", text: "Fine-tune")
      |> assert_has("button[aria-expanded=false]", text: "Fine-tune each dimension")
    end
  end

  describe "picking presets" do
    test "clicking a preset marks it aria-checked, others unchecked", %{conn: conn} do
      conn
      |> visit("/groups")
      |> click_button("[data-role=open_modal]", "Create a group")
      |> click_button("[data-preset=public_local_community]", "Public local community")
      |> assert_has("[data-preset=public_local_community][aria-checked=true]")
      |> refute_has("[data-preset=announcement_channel][aria-checked=true]")
      |> refute_has("[data-preset=custom][aria-checked=true]")
    end

    test "picking a non-Custom preset reveals Layer 2 fine-tune toggles", %{conn: conn} do
      conn
      |> visit("/groups")
      |> click_button("[data-role=open_modal]", "Create a group")
      |> click_button("[data-preset=public_local_community]", "Public local community")
      |> assert_has("h3", text: "Fine-tune")
      |> assert_has("*", text: "Discoverable in group listings")
      |> assert_has("*", text: "Require approval to join")
    end

    test "picking Custom hides Layer 2 and auto-opens Advanced", %{conn: conn} do
      conn
      |> visit("/groups")
      |> click_button("[data-role=open_modal]", "Create a group")
      |> click_button("[data-preset=custom]", "Custom")
      |> refute_has("h3", text: "Fine-tune")
      |> assert_has("button[aria-expanded=true]", text: "Fine-tune each dimension")
    end

    test "switching presets moves the check mark", %{conn: conn} do
      conn
      |> visit("/groups")
      |> click_button("[data-role=open_modal]", "Create a group")
      |> click_button("[data-preset=public_local_community]", "Public local community")
      |> assert_has("[data-preset=public_local_community][aria-checked=true]")
      |> click_button("[data-preset=announcement_channel]", "Announcement channel")
      |> assert_has("[data-preset=announcement_channel][aria-checked=true]")
      |> refute_has("[data-preset=public_local_community][aria-checked=true]")
    end
  end

  describe "Advanced region" do
    test "expanding Advanced reveals the four boundary dimension controls", %{conn: conn} do
      conn
      |> visit("/groups")
      |> click_button("[data-role=open_modal]", "Create a group")
      |> click_button("Fine-tune each dimension")
      |> assert_has("button[aria-expanded=true]", text: "Fine-tune each dimension")
      |> assert_has("*", text: "Who can join?")
      |> assert_has("*", text: "Who can see the group?")
      |> assert_has("*", text: "Who can post and interact?")
    end
  end

  describe "end-to-end creation via UI" do
    # We can't use PhoenixTest's `fill_in` here because the modal content lives in a
    # separate PersistentLive process, and PhoenixTest's label-based input lookup
    # doesn't resolve labels across that process boundary. Instead we `unwrap` into
    # LiveViewTest and submit the form directly — still exercises the full server
    # flow (phx-submit → Bonfire.UI.Groups:new → Categories.create → redirect).
    test "picking a preset + submitting creates a group in the DB", %{conn: conn} do
      name = "UI Test Group #{System.unique_integer([:positive])}"

      conn
      |> visit("/groups")
      |> click_button("[data-role=open_modal]", "Create a group")
      |> click_button("[data-preset=public_local_community]", "Public local community")
      |> submit_new_group_form(%{"name" => name, "summary" => "Created from the modal UI."})

      # LiveHandler returns {:redirect, ...} after create, which render_submit surfaces
      # as an error tuple from the LV process — the submit itself still ran, so the DB
      # is the source of truth.
      assert group_with_name_exists?(name),
             "expected a group named #{inspect(name)} to exist after submit"
    end

    # When Advanced is collapsed, the dimensions must still reach the form payload —
    # otherwise `resolve_dims/1` silently falls back to defaults regardless of preset.
    # Values are post-layer2 (preset's `layer2_defaults` are folded into primitives by
    # `apply_preset/2`), so for `public_local_community` (`discoverable: true,
    # anyone_posts: true`) the visibility becomes `nonfederated:discoverable` and
    # participation becomes `local:contributors`.
    test "after picking a preset (Advanced collapsed), the form carries the preset's dimensions as hidden inputs",
         %{conn: conn} do
      conn
      |> visit("/groups")
      |> click_button("[data-role=open_modal]", "Create a group")
      |> click_button("[data-preset=public_local_community]", "Public local community")
      |> assert_has(~s|input[type="hidden"][name="membership"][value="local:members"]|)
      |> assert_has(
        ~s|input[type="hidden"][name="visibility"][value="nonfederated:discoverable"]|
      )
      |> assert_has(~s|input[type="hidden"][name="participation"][value="local:contributors"]|)
      |> assert_has(
        ~s|input[type="hidden"][name="default_content_visibility"][value="nonfederated"]|
      )
    end
  end

  describe "input preservation (regression)" do
    test "both name and description round-trip to the backend intact", %{conn: conn} do
      # The pre-fix bug: typing in name cleared description (and vice versa) because
      # `phx-change=Bonfire.Classify:validate` triggered morphdom reconciliation
      # every keystroke, wiping the textarea contents server-side. Fix: drop the
      # no-op validate handler and add `phx-update=ignore` to both inputs.
      #
      # LiveViewTest can't reproduce the keystroke race (no real browser) but we
      # lock in the contract that both fields survive the submit path together.
      name = "Persistence Test #{System.unique_integer([:positive])}"
      summary = "Both fields should reach the server intact."

      conn
      |> visit("/groups")
      |> click_button("[data-role=open_modal]", "Create a group")
      |> click_button("[data-preset=public_local_community]", "Public local community")
      |> submit_new_group_form(%{"name" => name, "summary" => summary})

      assert group_with_name_exists?(name),
             "name field was dropped before reaching the backend"

      # Verify the summary landed on the created category's profile.
      profile_summary =
        from(c in Category,
          join: p in assoc(c, :profile),
          where: p.name == ^name,
          select: p.summary,
          limit: 1
        )
        |> Repo.one()

      assert profile_summary == summary,
             "expected summary to round-trip as #{inspect(summary)}, got #{inspect(profile_summary)}"
    end
  end

  describe "config integrity" do
    # These lock in the preset → boundary-dimension mapping contract.
    # Per DESIGN.md §"Layer 1 — Defaults": every preset must produce a complete,
    # working outcome (membership / visibility / participation / default_content_visibility
    # all filled in) so a user who stops at Layer 1 and clicks Create gets something
    # sensible. These tests break if someone drops a primitive from the config.

    test "every configured preset fills all four boundary dimensions" do
      for slug <- GroupBoundaryEditorLive.preset_slugs() do
        meta = GroupBoundaryEditorLive.preset_meta(slug)

        assert is_binary(meta[:label]), "preset #{slug} missing :label"
        assert is_binary(meta[:description]), "preset #{slug} missing :description"

        for dim <- [:membership, :visibility, :participation, :default_content_visibility] do
          assert is_binary(meta[dim]),
                 "preset #{slug} missing primitive :#{dim} — " <>
                   "violates DESIGN.md's 'complete, working outcome' rule"
        end
      end
    end

    # test "'secret_group' locks all four Layer 2 toggles" do
    #   assert GroupBoundaryEditorLive.layer2_locked?("secret_group", :federate)
    #   assert GroupBoundaryEditorLive.layer2_locked?("secret_group", :discoverable)
    #   assert GroupBoundaryEditorLive.layer2_locked?("secret_group", :approval_required)
    #   assert GroupBoundaryEditorLive.layer2_locked?("secret_group", :anyone_posts)
    # end

    test "'public_local_community' only locks federate" do
      assert GroupBoundaryEditorLive.layer2_locked?("public_local_community", :federate)
      refute GroupBoundaryEditorLive.layer2_locked?("public_local_community", :discoverable)
      refute GroupBoundaryEditorLive.layer2_locked?("public_local_community", :approval_required)
      refute GroupBoundaryEditorLive.layer2_locked?("public_local_community", :anyone_posts)
    end

    test "'announcement_channel' locks federate + anyone_posts but leaves discoverable + approval open" do
      assert GroupBoundaryEditorLive.layer2_locked?("announcement_channel", :federate)
      refute GroupBoundaryEditorLive.layer2_locked?("announcement_channel", :discoverable)
      refute GroupBoundaryEditorLive.layer2_locked?("announcement_channel", :approval_required)
      assert GroupBoundaryEditorLive.layer2_locked?("announcement_channel", :anyone_posts)
    end

    test "'private_club' locks federate + anyone_posts but leaves discoverable + approval open" do
      assert GroupBoundaryEditorLive.layer2_locked?("private_club", :federate)
      refute GroupBoundaryEditorLive.layer2_locked?("private_club", :discoverable)
      refute GroupBoundaryEditorLive.layer2_locked?("private_club", :approval_required)
      assert GroupBoundaryEditorLive.layer2_locked?("private_club", :anyone_posts)
    end
  end

  describe "Layer 2 toggles → primitives cascade" do
    # `public_local_community` is the densest preset for cascade testing — it leaves
    # :discoverable, :approval_required, and :anyone_posts all toggleable (only
    # :federate is locked). Each toggle has a deterministic effect on a primitive
    # via `apply_layer2_to_primitives/3` in `GroupBoundaryEditorLive`.

    test "toggling 'Require approval' on rewrites membership to on_request", %{conn: conn} do
      conn
      |> visit("/groups")
      |> click_button("[data-role=open_modal]", "Create a group")
      |> click_button("[data-preset=public_local_community]", "Public local community")
      |> assert_has(~s|input[type="hidden"][name="membership"][value="local:members"]|)
      |> click_layer2_toggle("approval_required")
      |> assert_has(~s|input[type="hidden"][name="membership"][value="on_request"]|)
    end

    test "toggling 'Anyone can post' off rewrites participation to group_members", %{conn: conn} do
      conn
      |> visit("/groups")
      |> click_button("[data-role=open_modal]", "Create a group")
      |> click_button("[data-preset=public_local_community]", "Public local community")
      |> assert_has(~s|input[type="hidden"][name="participation"][value="local:contributors"]|)
      |> click_layer2_toggle("anyone_posts")
      |> assert_has(~s|input[type="hidden"][name="participation"][value="group_members"]|)
    end
  end

  describe "preset-swap confirmation banner" do
    # When `layer2_touched=true`, picking a different preset must not silently
    # discard the user's edits — instead the editor stages the swap as
    # `pending_preset` and shows a banner with Apply / Keep actions.

    test "after touching Layer 2, picking a different preset shows the confirmation buttons",
         %{conn: conn} do
      conn
      |> visit("/groups")
      |> click_button("[data-role=open_modal]", "Create a group")
      |> click_button("[data-preset=public_local_community]", "Public local community")
      |> click_layer2_toggle("approval_required")
      |> click_button("[data-preset=announcement_channel]", "Announcement channel")
      |> assert_has("button", text: "Apply defaults")
      |> assert_has("button", text: "Keep my changes")
    end

    test "'Apply defaults' applies the new preset's primitives and clears the banner",
         %{conn: conn} do
      conn
      |> visit("/groups")
      |> click_button("[data-role=open_modal]", "Create a group")
      |> click_button("[data-preset=public_local_community]", "Public local community")
      |> click_layer2_toggle("approval_required")
      |> click_button("[data-preset=announcement_channel]", "Announcement channel")
      |> click_button("Apply defaults")
      |> assert_has("[data-preset=announcement_channel][aria-checked=true]")
      |> refute_has("button", text: "Apply defaults")
      |> assert_has(~s|input[type="hidden"][name="membership"][value="invite_only"]|)
    end

    test "'Keep my changes' cancels the swap and preserves the edited primitives",
         %{conn: conn} do
      conn
      |> visit("/groups")
      |> click_button("[data-role=open_modal]", "Create a group")
      |> click_button("[data-preset=public_local_community]", "Public local community")
      |> click_layer2_toggle("approval_required")
      |> click_button("[data-preset=announcement_channel]", "Announcement channel")
      |> click_button("Keep my changes")
      |> assert_has("[data-preset=public_local_community][aria-checked=true]")
      |> refute_has("button", text: "Apply defaults")
      |> assert_has(~s|input[type="hidden"][name="membership"][value="on_request"]|)
    end
  end

  describe "Custom preset submit path" do
    # Custom is the escape-hatch preset: Advanced auto-opens and `preset_slug` is
    # NOT emitted to the form payload (the dimension components emit their own
    # inputs instead). This locks in the contract so a future refactor doesn't
    # silently start sending preset_slug="custom" (which would fail to round-trip
    # through `Presets.group_dimension_slugs/1`).

    test "picking Custom does not emit a preset_slug hidden input", %{conn: conn} do
      conn
      |> visit("/groups")
      |> click_button("[data-role=open_modal]", "Create a group")
      |> click_button("[data-preset=custom]", "Custom")
      |> refute_has(~s|input[type="hidden"][name="preset_slug"]|)
    end

    test "submitting Custom with explicit dim values creates a group with those dims",
         %{conn: conn} do
      name = "Custom Dims #{System.unique_integer([:positive])}"

      conn
      |> visit("/groups")
      |> click_button("[data-role=open_modal]", "Create a group")
      |> click_button("[data-preset=custom]", "Custom")
      |> submit_new_group_form(%{
        "name" => name,
        "summary" => "Custom dims submission",
        "membership" => "invite_only",
        "visibility" => "local:discoverable",
        "participation" => "local:contributors",
        "default_content_visibility" => "members:private"
      })

      assert group_with_name_exists?(name),
             "expected a Custom-preset group named #{inspect(name)} to exist after submit"

      group =
        from(c in Category,
          join: p in assoc(c, :profile),
          where: p.name == ^name,
          preload: [:settings, :character]
        )
        |> Repo.one!()

      detected = Bonfire.Boundaries.Presets.group_dimension_slugs(group)

      assert detected.membership == "invite_only",
             "expected membership=invite_only, got #{inspect(detected.membership)}"

      assert detected.visibility == "local:discoverable",
             "expected visibility=local:discoverable, got #{inspect(detected.visibility)}"
    end
  end

  describe "admin instance circles in picker" do
    # `init_group_boundary_assigns/1` augments `@circles` with circles whose
    # caretaker is the instance admin_circle when the current user is an instance
    # admin. The picker (`BoundaryDimensionLive` / `BoundaryScopeSelectorLive`)
    # renders each circle's name inside the Advanced panel.

    test "admin user sees instance circles listed in the Advanced dimensions picker" do
      account = fake_account!()
      admin = fake_user!(account)
      {:ok, _} = Bonfire.Me.Users.make_admin(admin)

      name = "AdminInstCircle #{System.unique_integer([:positive])}"
      {:ok, _} = Bonfire.Boundaries.Circles.create(:instance, %{named: %{name: name}})

      conn(user: admin, account: account)
      |> visit("/groups")
      |> click_button("[data-role=open_modal]", "Create a group")
      |> click_button("[data-preset=public_local_community]", "Public local community")
      |> click_button("Fine-tune each dimension")
      |> assert_has("*", text: name)
    end

    test "non-admin user does not see instance circles in the Advanced dimensions picker",
         %{conn: conn} do
      name = "HiddenInstCircle #{System.unique_integer([:positive])}"
      {:ok, _} = Bonfire.Boundaries.Circles.create(:instance, %{named: %{name: name}})

      conn
      |> visit("/groups")
      |> click_button("[data-role=open_modal]", "Create a group")
      |> click_button("[data-preset=public_local_community]", "Public local community")
      |> click_button("Fine-tune each dimension")
      |> refute_has("*", text: name)
    end
  end
end
