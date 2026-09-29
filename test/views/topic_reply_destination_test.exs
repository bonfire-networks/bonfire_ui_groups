defmodule Bonfire.UI.Groups.TopicReplyDestinationTest do
  use Bonfire.UI.Groups.ConnCase, async: false
  @moduletag :ui

  for surface <- [:topic, :feed] do
    test "replying from #{surface} shows the group and topic without changing thread context" do
      account = fake_account!()
      user = fake_user!(account)
      group = Bonfire.Classify.Simulate.fake_group!(user, %{name: "Design collective", visibility: "global", membership: "open", participation: "anyone"})
      topic = Bonfire.Classify.Simulate.fake_category!(user, group, %{type: :topic, name: "Accessibility"})
      post = Bonfire.Classify.Simulate.fake_post_in_topic!(user, topic, "<p>Topic reply destination check</p>")
      path = if unquote(surface) == :topic, do: "/+#{topic.character.username}", else: "/feed/local"

      session = conn(user: user, account: account) |> visit(path) |> wait_async()
      session =
        if unquote(surface) == :topic do
          session
          |> assert_has("a.open_preview_link[href='/post/#{post.id}']")
          |> click_link("a.open_preview_link[href='/post/#{post.id}']", "")
          |> wait_async()
        else
          session
        end

      session
      |> PhoenixTest.unwrap(fn view ->
        view |> element("[data-id=action_reply][phx-value-id='#{post.id}']") |> render_click()
        composer = composer_view(view)
        render(composer)
        assert has_element?(composer, "[data-role=reply_destination]", "Design collective")
        assert has_element?(composer, "[data-role=reply_destination]", "Accessibility")
        assert has_element?(composer, "#composer_reply_destination", "Accessibility")
        assert has_element?(composer, "#composer_reply_actions_trigger", "Replying to")
        refute has_element?(composer, "#reply_banner")
        refute has_element?(composer, "#smart_input_post_title")
        assert has_element?(composer, "#reply_peek", "Topic reply destination check")
        assert has_element?(composer, "#composer_reply_actions_panel #convert_reply button", "Remove reply")
        assert has_element?(composer, "#composer_policy_controls", "Reply in")
        assert has_element?(composer, "#composer_policy_controls", "Same as original post")
        refute has_element?(composer, "#reply_peek [data-role=subject]")
        composer |> element("[data-reply-audience=reply_moderators]") |> render_click()
        assert has_element?(composer, "input[name='to_boundaries[]'][value=reply_moderators]")
        assert has_element?(composer, "input[name=context_id][value='#{post.id}']")
        render_click(composer, "Bonfire.UI.Common.SmartInput:select_reply_audience", %{"id" => "public"})
        refute has_element?(composer, "input[name='to_boundaries[]'][value=public]")
        composer |> element("[data-reply-audience=clone_context]") |> render_click()
        assert has_element?(composer, "#composer_reply_visibility_trigger", "Same as original post")
        refute has_element?(composer, "#reply_excerpt")
        assert has_element?(composer, "#composer_reply_actions_panel #toggle_reply_preview[aria-controls=reply_peek][aria-expanded=false]", "Show original post")
        refute has_element?(composer, "#reply_banner button[phx-click='Bonfire.UI.Common.SmartInput:remove_data']")
        assert has_element?(composer, "input[name=context_id][value='#{post.id}']")
        refute has_element?(composer, "#composer_audience_picker")
        refute has_element?(composer, "#composer_topic_controls")
        composer |> element("#smart_input_form") |> render_change(%{
          "post" => %{"post_content" => %{"html_body" => "Keep this draft"}},
          "_target" => ["post", "post_content", "html_body"]
        })
        assert has_element?(composer, "#smart_input_container[data-draft=true]")
        composer |> element("#convert_reply button[data-role=open_modal]") |> render_click()
        assert has_element?(composer, "#confirm_standalone_post", "Remove reply")
        assert has_element?(composer, "#composer_reply_actions")
        composer |> element("#persistent_modal .modal-action > div[phx-click=close]") |> render_click()
        assert has_element?(composer, "#composer_reply_actions")
        assert has_element?(composer, "input[name=context_id][value='#{post.id}']")
        assert has_element?(composer, "#smart_input_container[data-draft=true]")
        composer |> element("#convert_reply button[data-role=open_modal]") |> render_click()
        composer |> element("#confirm_standalone_post") |> render_click()
        render(composer)
        refute has_element?(composer, "[data-role=reply_destination]")
        assert has_element?(composer, "#composer_audience_picker")
        assert has_element?(composer, "#define_permissions button[aria-label='Custom boundaries']")
        refute has_element?(composer, "#composer_reply_actions")
        refute has_element?(composer, "#reply_peek")
        refute has_element?(composer, "[data-role=composer_recipients]")
        refute has_element?(composer, "input[name=context_id][value='#{post.id}']")
        assert has_element?(composer, "#smart_input_container[data-draft=true]")
        refute has_element?(composer, "#submit_btn[disabled]")
        assert has_element?(composer, "input[name='to_boundaries[]'][value=private]")
        refute has_element?(composer, "input[name='to_boundaries[]'][value=public]")
        render(view)
      end)
    end
  end
  test "personal replies start inherited and can select the original author" do
    account = fake_account!()
    user = fake_user!(account)
    author = fake_user!()
    {:ok, post} = Bonfire.Posts.publish(current_user: author,
      post_attrs: %{post_content: %{html_body: Faker.Lorem.sentence()}}, boundary: "public")
    conn(user: user, account: account)
    |> visit("/feed/local")
    |> wait_async()
    |> PhoenixTest.unwrap(fn view ->
      view |> element("[data-id=action_reply][phx-value-id='#{post.id}']") |> render_click()
      composer = composer_view(view)
      render(composer)
      assert has_element?(composer, "#composer_reply_visibility_trigger", "Same as original post")
      composer |> element("[data-reply-audience=reply_participants]") |> render_click()
      assert has_element?(composer, "#composer_reply_visibility_trigger", "Original author and you")
      assert has_element?(composer, "input[name='to_boundaries[]'][value=reply_participants]")
      assert has_element?(composer, "input[name=context_id][value='#{post.id}']")
      refute has_element?(composer, "[data-role=composer_recipients]")
      render(view)
    end)
  end

end
