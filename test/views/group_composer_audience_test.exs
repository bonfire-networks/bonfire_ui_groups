defmodule Bonfire.UI.Groups.GroupComposerAudienceTest do
  use Bonfire.UI.Groups.ConnCase, async: false
  @moduletag :ui

  test "group visibility dropdown offers only permitted audiences and preserves the topic" do
    account = fake_account!()
    owner = fake_user!(account)
    group = Bonfire.Classify.Simulate.fake_group!(owner, %{
      name: "Restricted audience choices", visibility: "members:private",
      default_content_visibility: "members:private"
    })
    topic = Bonfire.Classify.Simulate.fake_category!(owner, group, %{type: :topic, name: "Audience review"})
    conn(user: owner, account: account)
    |> visit("/feed/local")
    |> PhoenixTest.unwrap(fn view ->
      composer = composer_view(view)
      open_menu(composer, "composer_audience_picker")
      composer |> element("[data-audience-group='#{group.id}']") |> render_click()
      assert has_element?(composer, "#composer_group_visibility_trigger", "Members only")
      refute has_element?(composer, "[data-group-audience=public]")
      composer |> element("[data-group-audience=moderators]") |> render_click()
      assert has_element?(composer, "#composer_group_visibility_trigger", "Group moderators only")
      assert has_element?(composer, "input[name='to_boundaries[]'][value=moderators]")
      composer |> element("#composer_destination [phx-value-id='#{topic.id}']") |> render_click()
      assert has_element?(composer, "input[name=context_id][value='#{topic.id}']")
      assert has_element?(composer, "input[name='to_boundaries[]'][value=moderators]")
      render_click(composer, "Bonfire.UI.Common.SmartInput:select_group_audience", %{"id" => "public"})
      refute has_element?(composer, "input[name='to_boundaries[]'][value=public]")
      composer |> element("[data-group-audience='members:private']") |> render_click()
      assert has_element?(composer, "input[name='to_boundaries[]'][value='members:private']")
      assert has_element?(composer, "input[name=context_id][value='#{topic.id}']")
      render(view)
    end)
  end

  test "opening directly from a topic uses its parent audience choices" do
    account = fake_account!()
    owner = fake_user!(account)
    group = Bonfire.Classify.Simulate.fake_group!(owner, %{
      name: "Topic audience parent", visibility: "members:private",
      default_content_visibility: "members:private"
    })
    topic = Bonfire.Classify.Simulate.fake_category!(owner, group, %{type: :topic, name: "Direct topic entry"})
    conn(user: owner, account: account)
    |> visit("/+#{topic.character.username}")
    |> wait_async()
    |> click_button("#inline_composer_placeholder_open", "Start a discussion in Direct topic entry…")
    |> PhoenixTest.unwrap(fn view ->
      composer = composer_view(view)
      assert has_element?(composer, "#composer_group_visibility_trigger", "Members only")
      assert has_element?(composer, "#composer_audience_picker_trigger", "Topic audience parent")
      assert has_element?(composer, "[data-group-audience=moderators]")
      refute has_element?(composer, "[data-group-audience=public]")
      composer |> element("[data-group-audience=moderators]") |> render_click()
      assert has_element?(composer, "input[name=context_id][value='#{topic.id}']")
      assert has_element?(composer, "input[name='to_boundaries[]'][value=moderators]")
      render(view)
    end)
  end

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
      composer = composer_view(view)
      assert has_element?(composer, "[data-role=group-composer-audience]", "Members only")
      assert has_element?(composer, "header #composer_type_chooser")
      refute has_element?(composer, "#composer_publish_controls #composer_type_chooser")
      assert has_element?(composer, "#smart_input_more_options #discard_composer")

      assert has_element?(composer, "#composer_topic_controls #composer_destination_trigger", "Whole group")

      composer
      |> element("#composer_destination [phx-value-id='#{topic.id}']", "Design feedback")
      |> render_click()

      assert has_element?(composer, "input[name=context_id][value='#{topic.id}']")
      assert has_element?(composer, "#composer_audience_picker_trigger", "Private audience check")
      assert has_element?(composer, "#composer_destination_trigger", "Design feedback")
      assert has_element?(composer, "#composer_destination [phx-value-id='#{topic.id}'][aria-pressed=true]")

      composer
      |> element("#composer_destination [phx-value-id='#{group.id}']")
      |> render_click()

      composer
      |> element("#minimize_composer_button[aria-label='Minimise composer, keep draft']")
      |> render_click()

      assert has_element?(composer, "input[name=context_id][value='#{group.id}']")
      assert has_element?(composer, "input[name='to_boundaries[]'][value='members:private']")
      render(view)
    end)
  end
end
