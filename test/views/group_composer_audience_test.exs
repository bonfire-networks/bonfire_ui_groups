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
end
