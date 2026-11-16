defmodule Bonfire.UI.Groups.HostileNameRenderTest do
  @moduledoc """
  The name of a group or topic is text, so wherever it is shown it is escaped, never output as HTML.
  """
  use Bonfire.UI.Groups.ConnCase, async: false
  use Surface.LiveViewTest

  @moduletag :ui

  alias Bonfire.UI.Groups.Preview.GroupLive
  alias Bonfire.Classify.Web.Preview.CategoryLive
  alias Bonfire.Classify.TopicLive

  @payload "<img src=x onerror=alert(1)>"

  defp live_onerror?(html), do: html =~ ~r/<img[^>]*onerror/i

  defp category(name),
    do: %{
      id: Needle.UID.generate(),
      type: :group,
      profile: %{name: name, summary: nil},
      character: %{username: "hostile"}
    }

  defp render_group_card(object) do
    assigns = %{object: object}

    render_surface do
      ~F"""
      <GroupLive object={@object} permalink="/test" />
      """
    end
  end

  defp render_category_preview(object) do
    assigns = %{object: object}

    render_surface do
      ~F"""
      <CategoryLive object={@object} permalink="/test" />
      """
    end
  end

  defp render_topic_chip(object) do
    assigns = %{object: object}

    render_surface do
      ~F"""
      <TopicLive object={@object} />
      """
    end
  end

  for {card, renderer} <- [
        group_card: :group_card,
        category_preview: :category_preview,
        topic_chip: :topic_chip
      ] do
    test "#{card}: a hostile name renders without a live onerror" do
      refute live_onerror?(render(unquote(renderer), category(@payload)))
    end

    test "#{card}: a plain name is shown (control)" do
      assert render(unquote(renderer), category("Life drawing")) =~ "Life drawing"
    end
  end

  defp render(:group_card, object), do: render_group_card(object)
  defp render(:category_preview, object), do: render_category_preview(object)
  defp render(:topic_chip, object), do: render_topic_chip(object)
end
