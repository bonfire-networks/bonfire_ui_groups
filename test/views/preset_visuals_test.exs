defmodule Bonfire.UI.Groups.PresetVisualsTest do
  @moduledoc """
  Coverage for the preset → visual hint surface:

    * sidebar group icon (preset-derived, fallback users-three)
    * profile hero avatar slot icon when no custom avatar uploaded
    * preset badge on the hero (round-trip: stored slug → meta.label)

  Asserts at the structural level (`data-role` markers + iconify slug strings)
  rather than pixel-level so refactors of the Iconify component don't break us.
  """

  use Bonfire.UI.Groups.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  alias Bonfire.Classify.Categories

  defp create_group_with_preset(creator, slug, opts \\ []) do
    meta = Bonfire.Boundaries.Presets.group_preset_meta(slug)

    base =
      %{
        name: opts[:name] || "Preset #{slug} #{System.unique_integer([:positive])}",
        description: "preset visuals fixture",
        type: :group,
        preset_slug: slug
      }
      |> Map.merge(
        Map.take(meta, [:membership, :visibility, :participation, :default_content_visibility])
      )

    {:ok, group} = Categories.create(creator, base, true)
    group
  end

  describe "sidebar group icon" do
    test "renders the preset's iconify slug for a group with no avatar" do
      account = fake_account!()
      me = fake_user!(account)
      _group = create_group_with_preset(me, "private_club", name: "Sidebar Lock Group")

      {:ok, _view, html} = live(conn(user: me, account: account), "/groups")

      # data-role marker only renders on the no-avatar branch
      assert html =~ "data-role=\"group_preset_icon\""
      # The lock icon slug appears in the rendered iconify output
      assert html =~ "lock-duotone"
    end

    test "falls back to users-three icon when no preset slug is stored" do
      account = fake_account!()
      me = fake_user!(account)

      # No preset_slug — `group_icon/1` falls back to default
      {:ok, _group} =
        Categories.create(
          me,
          %{name: "No Preset Sidebar #{System.unique_integer([:positive])}", type: :group},
          true
        )

      {:ok, _view, html} = live(conn(user: me, account: account), "/groups")

      assert html =~ "data-role=\"group_preset_icon\""
      assert html =~ "users-three-duotone"
    end
  end

  describe "profile hero icon" do
    test "renders the preset icon in the hero avatar slot when no avatar is uploaded" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group_with_preset(me, "public_local_community", name: "Hero Campfire Group")

      {:ok, _view, html} = live(conn(user: me, account: account), "/&#{group.character.username}")

      assert html =~ "data-role=\"group_preset_icon\""
      assert html =~ "campfire-duotone"
    end

    test "uses AvatarLive (no preset-icon tile) for non-group character types" do
      # User profile pages are :user, not :group → preset-icon branch must not fire.
      account = fake_account!()
      me = fake_user!(account)

      {:ok, _view, html} = live(conn(user: me, account: account), "/@#{me.character.username}")

      refute html =~ "data-role=\"group_preset_icon\""
    end
  end

  # The badge on `ProfileHeroFullLive` is gated on `preset_slug_from_dims/1` matching
  # the group's actual stored dims to a configured preset. This locks in the matcher
  # so refactors of `:group_presets` config don't silently break the badge.
  describe "preset_slug_from_dims/1 (badge source)" do
    test "round-trips every configured preset's own dims back to its slug" do
      for slug <- Bonfire.UI.Groups.NewGroupFormLive.preset_slugs() do
        meta = Bonfire.Boundaries.Presets.group_preset_meta(slug)

        dims = %{
          membership: meta.membership,
          visibility: meta.visibility,
          participation: meta.participation
        }

        assert Bonfire.Boundaries.Presets.preset_slug_from_dims(dims) == slug,
               "preset #{slug}'s own dims should match back to #{slug}"
      end
    end

    test "returns nil for an unknown dim combination (custom group)" do
      assert Bonfire.Boundaries.Presets.preset_slug_from_dims(%{
               membership: "open",
               visibility: "global",
               participation: "anyone"
             }) == nil
    end
  end
end
