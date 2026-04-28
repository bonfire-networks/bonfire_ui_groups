defmodule Bonfire.UI.Groups.PresetRoundTripTest do
  @moduledoc """
  Property-style tests that exercise the full preset → ACLs → dim slugs cycle
  for every configured group preset. Catches drift between `:group_presets`,
  `:preset_acls`, and `:group_dim_acls` that example tests miss.

  Failure modes this catches that example tests don't:
    * adding a preset that references a dim slug with no `:preset_acls` entry
    * an ACL signature collision between dims (the `open`/`anyone` bug shape)
    * a `:group_dim_acls` entry that doesn't match what `apply_slugs` actually
      stores on a freshly-created group
  """

  use Bonfire.UI.Groups.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  import Ecto.Query
  alias Bonfire.Classify.Categories
  alias Bonfire.Boundaries.Presets

  defp create_group_from_preset(creator, preset_slug) do
    meta =
      Bonfire.Common.Config.get([:group_presets, preset_slug], %{}, :bonfire_classify)

    attrs =
      %{
        name: "Round Trip #{preset_slug} #{System.unique_integer([:positive])}",
        type: :group,
        preset_slug: preset_slug
      }
      |> Map.merge(
        Map.take(meta, [:membership, :visibility, :participation, :default_content_visibility])
      )

    {:ok, group} = Categories.create(creator, attrs, true)

    Bonfire.Common.Repo.maybe_preload(group, [:settings, :character])
  end

  describe "preset round-trip" do
    # For every active preset slug, create a group from it and walk its stored
    # ACLs back to dim slugs — assert they match what the preset declared.
    test "every active preset's declared dims survive create → detect" do
      account = fake_account!()
      me = fake_user!(account)

      for preset_slug <- Bonfire.UI.Groups.NewGroupFormLive.preset_slugs() do
        group = create_group_from_preset(me, preset_slug)
        detected = Presets.group_dimension_slugs(group)

        meta =
          Bonfire.Common.Config.get([:group_presets, preset_slug], %{}, :bonfire_classify)

        assert detected.membership == meta.membership,
               "preset #{preset_slug}: membership detected as #{inspect(detected.membership)}, declared #{inspect(meta.membership)}"

        assert detected.visibility == meta.visibility,
               "preset #{preset_slug}: visibility detected as #{inspect(detected.visibility)}, declared #{inspect(meta.visibility)}"

        # Participation may legitimately be `nil` when the preset uses a
        # circle-controlled slug like `group_members`/`moderators`.
        if meta.participation in ["anyone", "local:contributors", "archipelago:contributors"] do
          assert detected.participation == meta.participation,
                 "preset #{preset_slug}: participation detected as #{inspect(detected.participation)}, declared #{inspect(meta.participation)}"
        end
      end
    end

    test "preset_slug_from_dims reverses every preset's declared dims" do
      for preset_slug <- Bonfire.UI.Groups.NewGroupFormLive.preset_slugs() do
        meta =
          Bonfire.Common.Config.get([:group_presets, preset_slug], %{}, :bonfire_classify)

        dims = %{
          membership: meta.membership,
          visibility: meta.visibility,
          participation: meta.participation
        }

        assert Presets.preset_slug_from_dims(dims) == preset_slug,
               "#{preset_slug}'s own dims should reverse-match to #{preset_slug}, got #{inspect(Presets.preset_slug_from_dims(dims))}"
      end
    end

    # Form-submit variant — exercises the actual UI path (modal → preset card
    # click → form submit) rather than calling `Categories.create` directly.
    # Catches drift in the form-attribute shaping that the direct test misses.
    @tag :ui
    test "every preset's form-submit path stores dim slugs that detect back" do
      account = fake_account!()
      me = fake_user!(account)
      conn = conn(user: me, account: account)

      for preset_slug <- Bonfire.UI.Groups.NewGroupFormLive.preset_slugs() do
        name = "Form RT #{preset_slug} #{System.unique_integer([:positive])}"

        meta =
          Bonfire.Common.Config.get([:group_presets, preset_slug], %{}, :bonfire_classify)

        conn
        |> visit("/groups")
        |> click_button("[data-role=open_modal]", "Create a group")
        |> click_button("[data-preset=#{preset_slug}]", to_string(meta.label))
        |> PhoenixTest.unwrap(fn view ->
          view
          |> Phoenix.LiveViewTest.element("#new_group_form")
          |> Phoenix.LiveViewTest.render_submit(%{"name" => name, "summary" => ""})
        end)

        group =
          from(c in Bonfire.Classify.Category,
            join: p in assoc(c, :profile),
            where: p.name == ^name,
            preload: [:settings, :character]
          )
          |> Bonfire.Common.Repo.one!()

        detected = Presets.group_dimension_slugs(group)

        assert detected.membership == meta.membership,
               "form #{preset_slug}: membership detected #{inspect(detected.membership)}, declared #{inspect(meta.membership)}"

        assert detected.visibility == meta.visibility,
               "form #{preset_slug}: visibility detected #{inspect(detected.visibility)}, declared #{inspect(meta.visibility)}"
      end
    end
  end
end
