defmodule Bonfire.UI.Groups.GroupComposerAudienceTest do
  use Bonfire.UI.Groups.ConnCase, async: false
  @moduletag :ui

  test "opening the group composer explains its configured audience" do
    account = fake_account!()
    owner = fake_user!(account)

    group =
      Bonfire.Classify.Simulate.fake_group!(owner, %{
        name: "Private audience check",
        membership: "on_request",
        visibility: "nonfederated:preview",
        participation: "group_members",
        default_content_visibility: "members:private"
      })

    topic =
      Bonfire.Classify.Simulate.fake_category!(owner, group, %{
        type: :topic,
        name: "Design feedback"
      })

    conn(user: owner, account: account)
    |> visit("/&#{group.character.username}")
    |> wait_async()
    |> click_button(
      "#inline_composer_placeholder_open",
      "Start a discussion in Private audience check…"
    )
    |> PhoenixTest.unwrap(fn view ->
      assert has_element?(
               composer_view(view),
               "[data-role=group-composer-audience]",
               "Members only"
             )

      composer = composer_view(view)
      assert has_element?(composer, "#composer_publish_controls #composer_type_chooser")
      refute has_element?(composer, "header #composer_type_chooser")
      assert has_element?(composer, "#smart_input_more_options #discard_composer")

      composer
      |> element("#composer_destination [phx-value-id='#{topic.id}']", "Design feedback")
      |> render_click()

      assert has_element?(composer, "input[name=context_id][value='#{topic.id}']")
      refute has_element?(composer, "#composer_subtopic_chooser")

      composer
      |> element("#composer_destination [phx-value-id='#{group.id}']")
      |> render_click()

      composer
      |> element("#minimize_composer_button[aria-label='Close composer, keep draft']")
      |> render_click()

      assert has_element?(composer, "input[name=context_id][value='#{group.id}']")
      assert has_element?(composer, "input[name='to_boundaries[]'][value='members:private']")
      render(view)
    end)
  end
end
