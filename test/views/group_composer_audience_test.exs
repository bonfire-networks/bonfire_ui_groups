defmodule Bonfire.UI.Groups.GroupComposerAudienceTest do
  use Bonfire.UI.Groups.ConnCase, async: false
  @moduletag :ui

  test "group visibility dropdown offers only permitted audiences and preserves the topic" do
    account = fake_account!()
    owner = fake_user!(account)

    group =
      Bonfire.Classify.Simulate.fake_group!(owner, %{
        name: "Restricted audience choices",
        visibility: "members:private",
        default_content_visibility: "members:private"
      })

    topic =
      Bonfire.Classify.Simulate.fake_category!(owner, group, %{
        type: :topic,
        name: "Audience review"
      })

    conn(user: owner, account: account)
    |> visit("/feed/local")
    |> PhoenixTest.unwrap(fn view ->
      composer = composer_view(view)
      refute has_element?(composer, "#smart_input_post_title")
      open_menu(composer, "composer_audience_picker")
      composer |> element("[data-audience-group='#{group.id}']") |> render_click()
      assert has_element?(composer, "#composer_group_visibility_trigger", "Group members only")
      # the title appears once posting in a group, and is recommended there: without one, threadiverse servers list the post as a short post rather than a thread, and a title added later won't change that
      assert has_element?(composer, "#smart_input_post_title:not(.hidden) #composer_post_title")
      assert has_element?(composer, "#composer_post_title[placeholder=Recommended]")
      refute has_element?(composer, "[data-group-audience=public]")
      composer |> element("[data-group-audience=moderators]") |> render_click()
      assert has_element?(composer, "#composer_group_visibility_trigger", "Group moderators only")
      assert has_element?(composer, "input[name='to_boundaries[]'][value=moderators]")
      composer |> element("[data-audience-topic='#{topic.id}']") |> render_click()
      assert has_element?(composer, "input[name=context_id][value='#{topic.id}']")
      assert has_element?(composer, "input[name='to_boundaries[]'][value=moderators]")

      render_click(composer, "Bonfire.UI.Common.SmartInput:select_group_audience", %{
        "id" => "public"
      })

      refute has_element?(composer, "input[name='to_boundaries[]'][value=public]")
      composer |> element("[data-group-audience='members:private']") |> render_click()
      assert has_element?(composer, "input[name='to_boundaries[]'][value='members:private']")
      assert has_element?(composer, "input[name=context_id][value='#{topic.id}']")
      render(view)
    end)
  end

  # the software hosting a mirrored group may not know these audiences, and leak a post narrowed to them; it doesn't federate here, so that being a mirror is the only thing that changes what it offers
  test "the composer in a group mirrored from another server offers no members-only or moderators-only audience, nor accepts one" do
    account = fake_account!()
    owner = fake_user!(account)

    group =
      Bonfire.Classify.Simulate.fake_group!(owner, %{
        name: "Mirrored audience choices",
        visibility: "nonfederated",
        default_content_visibility: "nonfederated"
      })

    assert {:ok, _} =
             Bonfire.Federate.ActivityPub.Peered.save_canonical_uri(
               group,
               "https://elsewhere.local/c/mirrored_audiences"
             )

    assert_no_narrower_audiences(conn(user: owner, account: account), group, "nonfederated")
  end

  # its members and moderators on other servers would get such a post only if they follow its author
  test "the composer in a group hosted here that federates offers no members-only or moderators-only audience, nor accepts one" do
    account = fake_account!()
    owner = fake_user!(account)

    group =
      Bonfire.Classify.Simulate.fake_group!(owner, %{
        name: "Federating audience choices",
        visibility: "global",
        default_content_visibility: "public"
      })

    assert_no_narrower_audiences(conn(user: owner, account: account), group, "public")
  end

  defp assert_no_narrower_audiences(conn, group, offered) do
    conn
    |> visit("/&#{group.character.username}")
    |> wait_async()
    |> click_button("#inline_composer_placeholder_open", "Start a discussion…")
    |> PhoenixTest.unwrap(fn view ->
      composer = composer_view(view)
      assert has_element?(composer, "[data-group-audience='#{offered}']")
      refute has_element?(composer, "[data-group-audience='members:private']")
      refute has_element?(composer, "[data-group-audience=moderators]")

      for audience <- ["members:private", "moderators"] do
        render_click(composer, "Bonfire.UI.Common.SmartInput:select_group_audience", %{
          "id" => audience
        })

        refute has_element?(composer, "input[name='to_boundaries[]'][value='#{audience}']")
      end

      render(view)
    end)
  end

  test "opening directly from a topic uses its parent audience choices" do
    account = fake_account!()
    owner = fake_user!(account)

    group =
      Bonfire.Classify.Simulate.fake_group!(owner, %{
        name: "Topic audience parent",
        visibility: "members:private",
        default_content_visibility: "members:private"
      })

    topic =
      Bonfire.Classify.Simulate.fake_category!(owner, group, %{
        type: :topic,
        name: "Direct topic entry"
      })

    conn(user: owner, account: account)
    |> visit("/+#{topic.character.username}")
    |> wait_async()
    |> click_button(
      "#inline_composer_placeholder_open",
      "Start a discussion in Direct topic entry…"
    )
    |> PhoenixTest.unwrap(fn view ->
      composer = composer_view(view)
      assert has_element?(composer, "#composer_group_visibility_trigger", "Group members only")
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
      "Start a discussion…"
    )
    |> PhoenixTest.unwrap(fn view ->
      composer = composer_view(view)
      assert has_element?(composer, "[data-role=group-composer-audience]", "Group members only")
      assert has_element?(composer, "header #composer_type_chooser")
      refute has_element?(composer, "#composer_publish_controls #composer_type_chooser")
      assert has_element?(composer, "header #composer_close")

      # no topic yet: the place chip names just the group
      refute has_element?(
               composer,
               "#composer_audience_picker_trigger [data-role=destination_topic]"
             )

      assert has_element?(composer, "[data-role=post_in_whole_group][aria-pressed=true]")

      composer
      |> element("[data-audience-topic='#{topic.id}']", "Design feedback")
      |> render_click()

      assert has_element?(composer, "input[name=context_id][value='#{topic.id}']")
      assert has_element?(composer, "#composer_audience_picker_trigger", "Private audience check")

      assert has_element?(
               composer,
               "#composer_audience_picker_trigger [data-role=destination_topic]",
               "Design feedback"
             )

      assert has_element?(composer, "[data-audience-topic='#{topic.id}'][aria-pressed=true]")

      composer
      |> element("[data-role=post_in_whole_group]")
      |> render_click()

      composer
      |> element("#minimize_composer_button[aria-label='Minimise composer, keep draft']")
      |> render_click()

      assert has_element?(composer, "input[name=context_id][value='#{group.id}']")
      assert has_element?(composer, "input[name='to_boundaries[]'][value='members:private']")
      render(view)
    end)
  end

  # a group marked sensitive opens its composer with "sensitive" on, which the author can turn off: a prefill, not a rule
  describe "in a group marked sensitive" do
    setup do
      account = fake_account!()
      owner = fake_user!(account)

      group =
        Bonfire.Classify.Simulate.fake_group!(owner, %{
          name: "Sensitive composer",
          membership: "open",
          visibility: "global",
          participation: "anyone",
          default_content_visibility: "public"
        })

      %{owner: owner, group: group, conn: conn(user: owner, account: account)}
    end

    defp mark!(group), do: assert({:ok, _} = Bonfire.Social.Objects.set_sensitivity(group, true))

    defp open_group_composer(conn, group) do
      conn
      |> visit("/&#{group.character.username}")
      |> wait_async()
      |> click_button("#inline_composer_placeholder_open", "Start a discussion…")
    end

    # the post's mark, found by its unique text, since submitting the form does not hand it back
    defp stored_sensitive?(text) do
      post_id =
        repo().one!(
          from(pc in Bonfire.Data.Social.PostContent,
            where: ilike(pc.html_body, ^"%#{text}%"),
            select: pc.id
          )
        )

      {:ok, post} = Bonfire.Posts.read(post_id, skip_boundary_check: true)
      e(repo().maybe_preload(post, :sensitive), :sensitive, :is_sensitive, false) == true
    end

    test "the composer of a group not marked sensitive opens with sensitive off", %{
      conn: conn,
      group: group
    } do
      conn
      |> open_group_composer(group)
      |> PhoenixTest.unwrap(fn view ->
        composer = composer_view(view)
        assert has_element?(composer, "#sensitive_btn input[name=sensitive][value=false]")
        render(view)
      end)
    end

    test "the composer of a group marked sensitive opens with sensitive on", %{
      conn: conn,
      group: group
    } do
      mark!(group)

      conn
      |> open_group_composer(group)
      |> PhoenixTest.unwrap(fn view ->
        composer = composer_view(view)
        assert has_element?(composer, "#sensitive_btn input[name=sensitive][value=true]")
        assert has_element?(composer, "#sensitive_btn button[aria-pressed=true]")
        render(view)
      end)
    end

    test "the author can turn it off and the post is stored not sensitive", %{
      conn: conn,
      group: group
    } do
      mark!(group)

      conn
      |> open_group_composer(group)
      |> PhoenixTest.unwrap(fn view ->
        composer = composer_view(view)
        composer |> element("#sensitive_btn button") |> render_click()
        assert has_element?(composer, "#sensitive_btn input[name=sensitive][value=false]")

        form_html = composer |> element("#smart_input_form") |> render()
        [_, sensitive] = Regex.run(~r{name="sensitive" value="([^"]*)"}, form_html)

        submit_composer(view, "<p>turned off by its author</p>", %{"sensitive" => sensitive})
      end)

      assert stored_sensitive?("turned off by its author") == false
    end

    test "a post left with it on is stored sensitive", %{conn: conn, group: group} do
      mark!(group)

      conn
      |> open_group_composer(group)
      |> PhoenixTest.unwrap(fn view ->
        form_html = composer_view(view) |> element("#smart_input_form") |> render()
        [_, sensitive] = Regex.run(~r{name="sensitive" value="([^"]*)"}, form_html)

        submit_composer(view, "<p>left on as prefilled</p>", %{"sensitive" => sensitive})
      end)

      assert stored_sensitive?("left on as prefilled") == true
    end

    test "a reply in its thread opens with sensitive on too", %{
      conn: conn,
      owner: owner,
      group: group
    } do
      post =
        Bonfire.Classify.Simulate.fake_post_in_group!(owner, group, "<p>a post to reply to</p>")

      mark!(group)

      {:ok, view, _html} = live(conn, "/discussion/#{id(post)}")
      Bonfire.UI.Common.Testing.Helpers.live_async_wait(view)

      view
      |> element("[data-id=action_reply][phx-value-id='#{id(post)}']")
      |> render_click()

      composer = composer_view(view)
      render(composer)
      assert has_element?(composer, "#sensitive_btn input[name=sensitive][value=true]")
    end
  end
end
