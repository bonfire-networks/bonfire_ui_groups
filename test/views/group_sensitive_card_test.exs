defmodule Bonfire.UI.Groups.GroupSensitiveCardTest do
  @moduledoc """
  The card of a group or topic marked sensitive, wherever it shows: a badge, its banner and icon blurred, and its description hidden, until the person chooses to show them. Its name stays. To guests too, unlike post media.

  The search results half is in `bonfire_search` (`group_sensitive_results_test.exs`), which has the index setup.
  """
  use Bonfire.UI.Groups.ConnCase, async: false
  use Surface.LiveViewTest
  @moduletag :ui

  alias Bonfire.Classify.Categories
  alias Bonfire.Classify.Simulate
  alias Bonfire.Social.Objects
  alias Bonfire.UI.Groups.Preview.GroupLive

  @summary "Figure drawing from life, every week."

  setup do
    Process.put(:federating, false)
    account = fake_account!()
    owner = fake_user!(account)

    plain = group_with_images(owner, "Still lifes")
    marked = group_with_images(owner, "Life drawing")
    assert {:ok, _} = Objects.set_sensitivity(marked, true)

    %{account: account, owner: owner, plain: reload(plain), marked: reload(marked)}
  end

  defp group_with_images(owner, name) do
    group =
      Simulate.fake_group!(owner, %{
        name: name,
        summary: @summary,
        membership: "open",
        visibility: "global",
        participation: "anyone",
        default_content_visibility: "public"
      })

    media = Bonfire.Social.Fake.upload_media(:images, owner)

    {:ok, group} =
      Categories.update(owner, group, %{
        profile: %{icon_id: media.id, image_id: media.id, summary: @summary}
      })

    group
  end

  defp reload(category) do
    {:ok, got} = Categories.get(id(category), [:default, skip_boundary_check: true])
    Bonfire.Common.Repo.maybe_preload(got, profile: [:icon, :image])
  end

  defp card(object, showing_within) do
    assigns = %{object: object, showing_within: showing_within}

    render_surface do
      ~F"""
      <GroupLive object={@object} showing_within={@showing_within} permalink="/test" />
      """
    end
    |> Floki.parse_document!()
  end

  defp topic_card(object) do
    assigns = %{object: object}

    render_surface do
      ~F"""
      <Bonfire.Classify.Web.Preview.CategoryLive object={@object} permalink="/test" />
      """
    end
    |> Floki.parse_document!()
  end

  defp has?(doc, selector), do: Floki.find(doc, selector) != []

  describe "on /groups" do
    test "a group not marked sensitive has no badge, a clear icon and its description", %{
      account: account,
      owner: owner,
      plain: plain
    } do
      card = "#group-preview-#{id(plain)}"

      conn(user: owner, account: account)
      |> visit("/groups/discover")
      |> assert_has(card, text: "Still lifes")
      |> refute_has("#{card} [data-role=sensitive_badge]")
      |> refute_has("#{card} img[data-sensitive]")
      |> assert_has("#{card} [data-role=group-card-summary]", text: @summary)
      |> refute_has("#{card} [data-role=group-card-summary].hidden")
    end

    test "a group marked sensitive has a badge, a blurred icon, and its description hidden until shown",
         %{account: account, owner: owner, marked: marked} do
      card = "#group-preview-#{id(marked)}"

      conn(user: owner, account: account)
      |> visit("/groups/discover")
      |> assert_has(card, text: "Life drawing")
      |> assert_has("#{card} [data-role=sensitive_badge]")
      |> assert_has("#{card} img[data-sensitive]")
      |> assert_has("#{card} [data-role=group-card-summary].hidden", text: @summary)
    end

    test "a guest sees the same", %{marked: marked} do
      card = "#group-preview-#{id(marked)}"

      conn()
      |> visit("/groups")
      |> assert_has("#{card} [data-role=sensitive_badge]")
      |> assert_has("#{card} img[data-sensitive]")
    end
  end

  describe "the feed card" do
    test "of a group not marked sensitive is clear", %{plain: plain} do
      doc = card(plain, :feed)
      assert has?(doc, "[data-role=group-card-banner]"), "control: it has a banner"
      refute has?(doc, "[data-role=sensitive_badge]")
      refute has?(doc, "[data-role=group-card-banner][data-sensitive]")
      refute has?(doc, "img[data-sensitive]")
      refute has?(doc, "[data-role=group-card-summary].hidden")
    end

    test "of a group marked sensitive has a badge, its banner and icon blurred and its description hidden",
         %{marked: marked} do
      doc = card(marked, :feed)
      assert has?(doc, "[data-role=sensitive_badge]")
      assert has?(doc, "[data-role=group-card-banner][data-sensitive]")
      assert has?(doc, "img[data-sensitive]")
      assert has?(doc, "[data-role=group-card-summary].hidden")
      assert Floki.text(doc) =~ "Life drawing", "its name stays"
    end
  end

  describe "the compact card" do
    test "of a group not marked sensitive is clear", %{plain: plain} do
      doc = card(plain, :compact)
      refute has?(doc, "[data-role=sensitive_badge]")
      refute has?(doc, "img[data-sensitive]")
    end

    test "of a group marked sensitive has a badge and a blurred icon", %{marked: marked} do
      doc = card(marked, :compact)
      assert has?(doc, "[data-role=sensitive_badge]")
      assert has?(doc, "img[data-sensitive]")
      assert has?(doc, "[data-role=group-card-summary].hidden")
    end
  end

  describe "the default card" do
    test "of a group marked sensitive has a badge, a blurred icon and its description hidden", %{
      plain: plain,
      marked: marked
    } do
      refute has?(card(plain, nil), "[data-role=sensitive_badge]"), "control"

      doc = card(marked, nil)
      assert has?(doc, "[data-role=sensitive_badge]")
      assert has?(doc, "img[data-sensitive]")
      assert has?(doc, "[data-role=group-card-summary].hidden")
    end
  end

  # the icon shows outside the card too: in the sidebar it is left out (too small to blur), elsewhere blurred
  describe "outside the card" do
    test "the sidebar shows the icon of a group not marked sensitive, and not that of one marked", %{
      account: account,
      owner: owner,
      plain: plain,
      marked: marked
    } do
      row = fn group -> "[data-role=sidebar-group][id$='-group-#{id(group)}']" end

      conn(user: owner, account: account)
      |> visit("/groups")
      |> assert_has(row.(plain), text: "Still lifes")
      |> assert_has("#{row.(plain)} [style*=background-image]")
      |> assert_has(row.(marked), text: "Life drawing")
      |> refute_has("#{row.(marked)} [style*=background-image]")
    end

    test "the archived list blurs the icon of a group marked sensitive", %{
      account: account,
      owner: owner,
      plain: plain,
      marked: marked
    } do
      assert {:ok, _} = Categories.soft_delete(plain, owner)
      assert {:ok, _} = Categories.soft_delete(marked, owner)

      conn(user: owner, account: account)
      |> visit("/groups/archived")
      |> assert_has("img[src][class*=grayscale]:not([data-sensitive])")
      |> assert_has("img[data-sensitive]")
    end
  end

  describe "the topic card outside search" do
    test "of a topic marked sensitive has a badge, a blurred icon and its description hidden", %{
      owner: owner,
      plain: plain
    } do
      topic = Simulate.fake_category!(owner, plain, %{name: "Charcoal", type: :topic})
      media = Bonfire.Social.Fake.upload_media(:images, owner)

      {:ok, _} =
        Categories.update(owner, topic, %{profile: %{icon_id: media.id, summary: @summary}})

      refute has?(topic_card(reload(topic)), "[data-role=sensitive_badge]"), "control"

      assert {:ok, _} = Objects.set_sensitivity(topic, true)
      doc = topic_card(reload(topic))
      assert has?(doc, "[data-role=sensitive_badge]")
      # its icon is a `LazyImage`, so the mark is on the box around it
      assert has?(doc, "[data-role=group-card-icon][data-sensitive]")
      assert has?(doc, "[data-role=group-card-summary].hidden")
    end
  end
end
