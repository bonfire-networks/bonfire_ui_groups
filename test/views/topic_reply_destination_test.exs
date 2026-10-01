defmodule Bonfire.UI.Groups.TopicReplyDestinationTest do
  use Bonfire.UI.Groups.ConnCase, async: false
  @moduletag :ui

  describe "replying to a post in a group topic" do
    setup do
      account = fake_account!()
      user = fake_user!(account)

      group =
        Bonfire.Classify.Simulate.fake_group!(user, %{
          name: "Design collective",
          visibility: "global",
          membership: "open",
          participation: "anyone"
        })

      topic =
        Bonfire.Classify.Simulate.fake_category!(user, group, %{
          type: :topic,
          name: "Accessibility"
        })

      post =
        Bonfire.Classify.Simulate.fake_post_in_topic!(
          user,
          topic,
          "<p>Topic reply destination check</p>"
        )

      {:ok, conn: conn(user: user, account: account), topic: topic, post: post}
    end

    for surface <- [:topic, :feed] do
      test "from the #{surface}, shows the group and topic as a fixed destination", context do
        context.conn
        |> open_reply(context.post, unquote(surface), context.topic)
        |> PhoenixTest.unwrap(fn view ->
          composer = composer_view(view)
          assert has_element?(composer, "#composer_reply_destination", "Design collective")
          assert has_element?(composer, "#composer_reply_destination", "Accessibility")
          assert has_element?(composer, "#composer_policy_controls", "Reply in")

          assert has_element?(
                   composer,
                   "#composer_reply_visibility_trigger",
                   "Same as original post"
                 )

          assert has_element?(composer, "#composer_reply_actions_trigger", "Replying to")
          assert has_element?(composer, "#reply_peek", "Topic reply destination check")
          # the preview omits the author, already named in the header
          refute has_element?(composer, "#reply_peek [data-role=subject]")

          assert has_element?(
                   composer,
                   "#toggle_reply_preview[aria-controls=reply_peek][aria-expanded=false]",
                   "Show original post"
                 )

          # replies keep their thread: no title, destination picker or topic choice
          refute has_element?(composer, "#smart_input_post_title")
          refute has_element?(composer, "#composer_audience_picker")
          refute has_element?(composer, "#composer_topic_controls")
          assert has_element?(composer, "input[name=context_id][value='#{context.post.id}']")
          render(view)
        end)
      end
    end

    test "reply visibility only accepts audiences the parent allows", context do
      context.conn
      |> open_reply(context.post, :feed)
      |> PhoenixTest.unwrap(fn view ->
        composer = composer_view(view)
        composer |> element("[data-reply-audience=reply_moderators]") |> render_click()
        assert has_element?(composer, "input[name='to_boundaries[]'][value=reply_moderators]")

        # a forged, broader choice is rejected by the server
        render_click(composer, "Bonfire.UI.Common.SmartInput:select_reply_audience", %{
          "id" => "public"
        })

        refute has_element?(composer, "input[name='to_boundaries[]'][value=public]")

        composer |> element("[data-reply-audience=clone_context]") |> render_click()

        assert has_element?(
                 composer,
                 "#composer_reply_visibility_trigger",
                 "Same as original post"
               )

        assert has_element?(composer, "input[name=context_id][value='#{context.post.id}']")
        render(view)
      end)
    end

    test "a minimised draft leaves a bar to resume it", context do
      context.conn
      |> open_reply(context.post, :feed)
      |> PhoenixTest.unwrap(fn view ->
        composer = composer_view(view)
        refute has_element?(composer, "#composer_draft_bar")
        type_draft(composer)

        composer |> element("#minimize_composer_button") |> render_click()
        assert has_element?(composer, "#smart_input_container[data-hidden]")
        assert has_element?(composer, "#composer_draft_bar", "Draft in progress")

        composer |> element("#composer_draft_bar") |> render_click()
        refute has_element?(composer, "#smart_input_container[data-hidden]")
        assert has_element?(composer, "#smart_input_container[data-draft=true]")
        assert has_element?(composer, "input[name=context_id][value='#{context.post.id}']")

        # resuming from the compose button keeps the draft too, so minimising again shows the bar
        composer |> element("#minimize_composer_button") |> render_click()
        composer |> element("#main_smart_input_button") |> render_click()
        assert has_element?(composer, "#smart_input_container[data-draft=true]")
        refute has_element?(composer, "#submit_btn[disabled]")
        composer |> element("#minimize_composer_button") |> render_click()
        assert has_element?(composer, "#composer_draft_bar")
        render(view)
      end)
    end

    test "removing a reply asks first, then keeps the draft as a private profile post", context do
      context.conn
      |> open_reply(context.post, :feed)
      |> PhoenixTest.unwrap(fn view ->
        composer = composer_view(view)
        type_draft(composer)

        # cancelling keeps replying, with the draft
        composer |> element("#convert_reply button[data-role=open_modal]") |> render_click()
        assert has_element?(composer, "#confirm_standalone_post", "Remove reply")

        composer
        |> element("#persistent_modal .modal-action > div[phx-click=close]")
        |> render_click()

        assert has_element?(composer, "#composer_reply_actions")
        assert has_element?(composer, "input[name=context_id][value='#{context.post.id}']")
        assert has_element?(composer, "#smart_input_container[data-draft=true]")

        # confirming turns it into a new post, without any of the reply's addressing, and publishes nothing
        posts_before = post_count()
        composer |> element("#convert_reply button[data-role=open_modal]") |> render_click()
        composer |> element("#confirm_standalone_post") |> render_click()
        assert post_count() == posts_before
        refute has_element?(composer, "#composer_reply_destination")
        refute has_element?(composer, "#composer_reply_actions")
        refute has_element?(composer, "#reply_peek")
        refute has_element?(composer, "[data-role=composer_recipients]")
        refute has_element?(composer, "input[name=context_id][value='#{context.post.id}']")
        assert has_element?(composer, "#composer_audience_picker")

        assert has_element?(
                 composer,
                 "#define_permissions button[aria-label='Custom boundaries']"
               )

        assert has_element?(composer, "input[name='to_boundaries[]'][value=private]")
        assert has_element?(composer, "#smart_input_container[data-draft=true]")
        refute has_element?(composer, "#submit_btn[disabled]")
        render(view)
      end)
    end
  end

  test "personal replies start inherited and can select the original author" do
    account = fake_account!()
    user = fake_user!(account)
    author = fake_user!()

    {:ok, post} =
      Bonfire.Posts.publish(
        current_user: author,
        post_attrs: %{post_content: %{html_body: Faker.Lorem.sentence()}},
        boundary: "public"
      )

    conn(user: user, account: account)
    |> open_reply(post, :feed)
    |> PhoenixTest.unwrap(fn view ->
      composer = composer_view(view)
      assert has_element?(composer, "#composer_reply_visibility_trigger", "Same as original post")
      composer |> element("[data-reply-audience=reply_participants]") |> render_click()

      assert has_element?(
               composer,
               "#composer_reply_visibility_trigger",
               "Original author and you"
             )

      assert has_element?(composer, "input[name='to_boundaries[]'][value=reply_participants]")
      assert has_element?(composer, "input[name=context_id][value='#{post.id}']")
      refute has_element?(composer, "[data-role=composer_recipients]")
      render(view)
    end)
  end

  # Presses Reply on `post`, from its topic page (opening the post first) or from the local feed.
  defp open_reply(conn, post, surface, topic \\ nil)

  defp open_reply(conn, post, :topic, topic) do
    conn
    |> visit("/+#{topic.character.username}")
    |> wait_async()
    |> click_link("a.open_preview_link[href='/post/#{post.id}']", "")
    |> wait_async()
    |> press_reply(post)
  end

  defp open_reply(conn, post, :feed, _topic) do
    conn
    |> visit("/feed/local")
    |> wait_async()
    |> press_reply(post)
  end

  defp press_reply(session, post) do
    PhoenixTest.unwrap(session, fn view ->
      view |> element("[data-id=action_reply][phx-value-id='#{post.id}']") |> render_click()
      # the press reaches the composer as a message to its `PersistentLive`; rendering that
      # child is a synchronous call, so the reply is set up before a test reads the composer
      view |> composer_view() |> render()
    end)
  end

  defp post_count, do: Bonfire.Common.Repo.aggregate(Bonfire.Data.Social.Post, :count)

  defp type_draft(composer) do
    composer
    |> element("#smart_input_form")
    |> render_change(%{
      "post" => %{"post_content" => %{"html_body" => "Keep this draft"}},
      "_target" => ["post", "post_content", "html_body"]
    })

    assert has_element?(composer, "#smart_input_container[data-draft=true]")
  end
end
