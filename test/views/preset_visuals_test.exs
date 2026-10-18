defmodule Bonfire.UI.Groups.PresetVisualsTest do
  @moduledoc """
  Coverage for the preset → visual hint surface:

    * sidebar group icon (preset-derived, fallback users-three)
    * profile hero avatar slot icon when no custom avatar uploaded
    * preset badge on the hero (round-trip: stored slug → meta.label)

  Asserts at the structural level (`data-role` markers + iconify slug strings)
  rather than pixel-level so refactors of the Iconify component don't break us.
  """

  # async: false — passes in isolation (6/6) but the group-icon iconify assertion fails under the
  # concurrent ui battery (shared render/state race); run serially
  use Bonfire.UI.Groups.ConnCase, async: false
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
    test "shows a letter tile and a lock for a private group with no avatar" do
      account = fake_account!()
      me = fake_user!(account)
      _group = create_group_with_preset(me, "private_club", name: "Sidebar Lock Group")

      {:ok, _view, html} = live(conn(user: me, account: account), "/groups")

      # the tile only renders on the no-avatar branch; privacy is shown as a lock after the name
      assert html =~ "data-role=\"group_tile\""
      assert html =~ "data-role=\"group_private\""
    end

    test "shows a letter tile without a lock when the dimensions match no preset" do
      account = fake_account!()
      me = fake_user!(account)

      # A group created without dimensions gets `on_request` + `local:unlisted` from
      # `resolve_dims/1`, a pair no configured preset declares, so `group_icon/2` has nothing to
      # back-translate to and returns the default
      {:ok, _group} =
        Categories.create(
          me,
          %{name: "No Preset Sidebar #{System.unique_integer([:positive])}", type: :group},
          true
        )

      {:ok, _view, html} = live(conn(user: me, account: account), "/groups")

      assert html =~ "data-role=\"group_tile\""
      refute html =~ "data-role=\"group_private\""
    end
  end

  # The badge on `ProfileHeroFullLive` is gated on `preset_slug_from_dims/1` matching
  # the group's actual stored dims to a configured preset. This locks in the matcher
  # so refactors of `:group_presets` config don't silently break the badge.
  describe "preset_slug_from_dims/1 (badge source)" do
    test "round-trips every configured preset's own dims back to its slug" do
      for slug <- Bonfire.UI.Groups.GroupBoundaryEditorLive.preset_slugs() do
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

    # open + global + anyone is `open_network` now, so the custom case federates but restricts posting, which no preset declares
    test "returns nil for an unknown dim combination (custom group)" do
      assert Bonfire.Boundaries.Presets.preset_slug_from_dims(%{
               membership: "open",
               visibility: "global",
               participation: "moderators"
             }) == nil
    end
  end
end
