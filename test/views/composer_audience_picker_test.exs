defmodule Bonfire.UI.Groups.ComposerAudiencePickerTest do
  use Bonfire.UI.Groups.ConnCase, async: false
  @moduletag :ui

  test "audiences, circles and groups are only loaded once each picker is opened" do
    account = fake_account!()
    user = fake_user!(account)
    {:ok, circle} = Bonfire.Boundaries.Circles.create(user, "Lazy circle")
    group = Bonfire.Classify.Simulate.fake_group!(user, %{name: "Lazy loading collective"})

    conn(user: user, account: account)
    |> visit("/feed/local")
    |> PhoenixTest.unwrap(fn view ->
      composer = composer_view(view)
      refute has_element?(composer, "[data-audience-group='#{group.id}']")
      refute has_element?(composer, "[data-audience-preset]")
      refute has_element?(composer, "[data-audience-circle='#{circle.id}']")

      open_menu(composer, "composer_audience_picker")
      assert has_element?(composer, "[data-audience-group='#{group.id}']")
      refute has_element?(composer, "[data-audience-preset]")

      open_menu(composer, "composer_visibility_picker")
      assert has_element?(composer, "[data-audience-preset=public]")
      assert has_element?(composer, "[data-audience-circle='#{circle.id}']")
      render(view)
    end)
  end

  test "search finds writable groups and returning to your profile clears group context" do
    account = fake_account!()
    user = fake_user!(account)
    group = Bonfire.Classify.Simulate.fake_group!(user, %{
      name: "Needle design collective",
      membership: "on_request",
      visibility: "nonfederated:preview",
      participation: "group_members",
      default_content_visibility: "members:private"
    })

    conn(user: user, account: account)
    |> visit("/feed/local")
    |> PhoenixTest.unwrap(fn view ->
      composer = composer_view(view)
      assert has_element?(composer, "#composer_audience_picker_trigger")
      composer |> element("#smart_input_form") |> render_change(%{
        "post" => %{"post_content" => %{"html_body" => "Keep this draft"}},
        "_target" => ["post", "post_content", "html_body"]
      })
      assert has_element?(composer, "#smart_input_container[data-draft=true]")
      open_menu(composer, "composer_audience_picker")
      composer |> element("#composer_audience_picker_search_form") |> render_change(%{"search" => "no-such-audience-xyz"})
      assert has_element?(composer, "#composer_audience_picker [role=status]", "No matching joined groups")
      composer |> element("#composer_audience_picker_search_form") |> render_change(%{"search" => "Needle"})
      assert has_element?(composer, "[data-audience-group='#{group.id}']", "Needle design collective")
      refute has_element?(composer, "#composer_audience_picker [data-audience-preset]")
      composer |> element("[data-audience-group='#{group.id}']") |> render_click()
      assert has_element?(composer, "input[name=context_id][value='#{group.id}']")
      assert has_element?(composer, "[data-role=group-composer-audience]", "Members only")
      refute has_element?(composer, "#composer_topic_controls")
      # minimising and resuming keeps the group destination
      composer |> element("#minimize_composer_button") |> render_click()
      composer |> element("#composer_draft_bar") |> render_click()
      assert has_element?(composer, "input[name=context_id][value='#{group.id}']")
      assert has_element?(composer, "#composer_audience_picker_trigger", "Needle design collective")
      composer |> element("[data-role=post_in_profile]") |> render_click()
      refute has_element?(composer, "input[name=context_id][value='#{group.id}']")
      assert has_element?(composer, "#composer_audience_picker_trigger", "Your profile")
      assert has_element?(composer, "#define_permissions")
      assert has_element?(composer, "#smart_input_container[data-draft=true]")
      refute has_element?(composer, "#submit_btn[disabled]")
      render(view)
    end)
  end

  test "personal visibility changes independently of the publication destination" do
    account = fake_account!()
    user = fake_user!(account)
    conn(user: user, account: account)
    |> visit("/feed/local")
    |> PhoenixTest.unwrap(fn view ->
      composer = composer_view(view)
      open_menu(composer, "composer_visibility_picker")
      composer |> element("[data-audience-preset=local]") |> render_click()
      assert has_element?(composer, "input[name='to_boundaries[]'][value=local]")
      assert has_element?(composer, "#composer_audience_picker_trigger", "Your profile")
      composer |> element("[data-role=post_in_profile]") |> render_click()
      assert has_element?(composer, "input[name='to_boundaries[]'][value=local]")
      refute has_element?(composer, "#composer_visibility_picker [data-audience-group]")
      render(view)
    end)
  end

  test "visibility offers owned circles with participate access and keeps custom boundaries in the menu" do
    account = fake_account!()
    user = fake_user!(account)
    {:ok, circle} = Bonfire.Boundaries.Circles.create(user, "Close friends")
    {:ok, other} = Bonfire.Boundaries.Circles.create(user, "Team")
    {:ok, foreign} = Bonfire.Boundaries.Circles.create(fake_user!(), "Someone else's circle")

    conn(user: user, account: account)
    |> visit("/feed/local")
    |> PhoenixTest.unwrap(fn view ->
      composer = composer_view(view)
      assert has_element?(composer, "#composer_visibility_picker #define_permissions", "Custom boundaries")
      refute has_element?(composer, "#composer_audience_picker [data-audience-circle]")
      refute has_element?(composer, "[data-audience-circle='#{foreign.id}']")
      open_menu(composer, "composer_visibility_picker")
      composer |> element("#composer_visibility_picker_search_form") |> render_change(%{"search" => "Close"})
      assert has_element?(composer, "[data-audience-circle='#{circle.id}']")
      refute has_element?(composer, "[data-audience-circle='#{other.id}']")
      composer |> element("[data-audience-circle='#{circle.id}']") |> render_click()
      assert has_element?(composer, "input[name='to_boundaries[]'][value=private]")
      assert has_element?(composer, "input[name='to_circles[#{circle.id}]'][value=participate]")
      assert has_element?(composer, "[data-audience-circle='#{circle.id}'][aria-pressed=true]")
      composer |> element("#composer_visibility_picker_search_form") |> render_change(%{"search" => ""})
      composer |> element("[data-audience-circle='#{other.id}']") |> render_click()
      assert has_element?(composer, "input[name='to_circles[#{circle.id}]'][value=participate]")
      assert has_element?(composer, "input[name='to_circles[#{other.id}]'][value=participate]")
      composer |> element("[data-audience-circle='#{circle.id}']") |> render_click()
      refute has_element?(composer, "input[name='to_circles[#{circle.id}]']")
      composer |> element("[data-audience-circle='#{other.id}']") |> render_click()
      assert has_element?(composer, "input[name='to_boundaries[]'][value=private]")
      render_click(composer, "Bonfire.UI.Common.SmartInput:toggle_audience_circle", %{"id" => foreign.id})
      refute has_element?(composer, "input[name='to_circles[#{foreign.id}]']")
      composer |> element("[data-audience-preset=public]") |> render_click()
      assert has_element?(composer, "input[name='to_boundaries[]'][value=public]")
      render(view)
    end)
  end

  test "saved boundary presets are offered as audiences, and someone else's cannot be forged" do
    account = fake_account!()
    user = fake_user!(account)

    {:ok, mine} =
      Bonfire.Boundaries.Acls.create(%{named: %{name: "Book club preset"}}, current_user: user)

    {:ok, foreign} =
      Bonfire.Boundaries.Acls.create(%{named: %{name: "Not my preset"}}, current_user: fake_user!())

    conn(user: user, account: account)
    |> visit("/feed/local")
    |> PhoenixTest.unwrap(fn view ->
      composer = composer_view(view)
      open_menu(composer, "composer_visibility_picker")
      assert has_element?(composer, "[data-audience-preset='#{mine.id}']", "Book club preset")
      refute has_element?(composer, "[data-audience-preset='#{foreign.id}']")

      composer |> element("[data-audience-preset='#{mine.id}']") |> render_click()
      assert has_element?(composer, "input[name='to_boundaries[]'][value='#{mine.id}']")

      render_click(composer, "Bonfire.UI.Common.SmartInput:select_audience", %{"id" => foreign.id})
      refute has_element?(composer, "input[name='to_boundaries[]'][value='#{foreign.id}']")
      assert has_element?(composer, "input[name='to_boundaries[]'][value='#{mine.id}']")
      render(view)
    end)
  end

  test "the selected circle's submitted boundary grants participation without public access" do
    account = fake_account!()
    user = fake_user!(account)
    member = fake_user!()
    outsider = fake_user!()
    {:ok, circle} = Bonfire.Boundaries.Circles.create(user, "Reviewers")
    {:ok, _} = Bonfire.Boundaries.Circles.add_to_circles(member.id, circle)

    conn(user: user, account: account)
    |> visit("/feed/local")
    |> PhoenixTest.unwrap(fn view ->
      composer = composer_view(view)
      open_menu(composer, "composer_visibility_picker")
      composer |> element("[data-audience-circle='#{circle.id}']") |> render_click()
      html = composer |> render() |> Floki.parse_document!()
      [boundary] = Floki.attribute(html, "input[name='to_boundaries[]']", "value")
      [role] = Floki.attribute(html, "input[name='to_circles[#{circle.id}]']", "value")
      {:ok, post} = Bonfire.Posts.publish(
        current_user: user,
        post_attrs: %{post_content: %{html_body: Faker.Lorem.sentence()}},
        boundary: boundary,
        to_circles: [{circle.id, role}]
      )
      for verb <- [:see, :read, :reply] do
        assert Bonfire.Boundaries.can?(member, verb, post)
        refute Bonfire.Boundaries.can?(outsider, verb, post)
        refute Bonfire.Boundaries.can?(:guest, verb, post)
      end
      render(view)
    end)
  end

  test "changing groups resets the optional topic and returning to personal clears it" do
    account = fake_account!()
    user = fake_user!(account)
    group = Bonfire.Classify.Simulate.fake_group!(user, %{name: "First topic collective"})
    other_group = Bonfire.Classify.Simulate.fake_group!(user, %{name: "Second topic collective"})
    topic = Bonfire.Classify.Simulate.fake_category!(user, group, %{type: :topic, name: "Design feedback"})
    other_topic = Bonfire.Classify.Simulate.fake_category!(user, other_group, %{type: :topic, name: "Planning"})

    conn(user: user, account: account)
    |> visit("/feed/local")
    |> PhoenixTest.unwrap(fn view ->
      composer = composer_view(view)
      open_menu(composer, "composer_audience_picker")
      composer |> element("[data-audience-group='#{group.id}']") |> render_click()
      assert has_element?(composer, "#composer_destination_trigger", "Whole group")
      composer |> element("#composer_destination [phx-value-id='#{topic.id}']") |> render_click()
      assert has_element?(composer, "input[name=context_id][value='#{topic.id}']")
      assert has_element?(composer, "#composer_audience_picker_trigger", "First topic collective")

      composer |> element("[data-audience-group='#{other_group.id}']") |> render_click()
      assert has_element?(composer, "input[name=context_id][value='#{other_group.id}']")
      assert has_element?(composer, "#composer_destination_trigger", "Whole group")
      refute has_element?(composer, "#composer_destination [phx-value-id='#{topic.id}']")
      composer |> element("#composer_destination [phx-value-id='#{other_topic.id}']") |> render_click()
      assert has_element?(composer, "input[name=context_id][value='#{other_topic.id}']")

      composer |> element("[data-role=post_in_profile]") |> render_click()
      refute has_element?(composer, "#composer_topic_controls")
      refute has_element?(composer, "input[name=context_id][value='#{other_topic.id}']")
      assert has_element?(composer, "#composer_audience_picker_trigger", "Your profile")
      render(view)
    end)
  end

  test "only joined writable groups appear, including when searching" do
    account = fake_account!()
    user = fake_user!(account)
    owner = fake_user!()
    attrs = %{membership: "open", visibility: "global", participation: "anyone"}
    joined = Bonfire.Classify.Simulate.fake_group!(owner, Map.put(attrs, :name, "Picker joined collective"))
    unjoined = Bonfire.Classify.Simulate.fake_group!(owner, Map.put(attrs, :name, "Picker unjoined collective"))
    readonly = Bonfire.Classify.Simulate.fake_group!(owner, Map.merge(attrs, %{name: "Picker announcements", participation: "moderators"}))
    {:ok, _} = Bonfire.Classify.Categories.join_group(user, joined)
    {:ok, _} = Bonfire.Classify.Categories.join_group(user, readonly)

    conn(user: user, account: account)
    |> visit("/feed/local")
    |> PhoenixTest.unwrap(fn view ->
      composer = composer_view(view)
      open_menu(composer, "composer_audience_picker")
      assert has_element?(composer, "[data-audience-group='#{joined.id}']")
      refute has_element?(composer, "[data-audience-group='#{unjoined.id}']")
      refute has_element?(composer, "[data-audience-group='#{readonly.id}']")
      composer |> element("#composer_audience_picker_search_form") |> render_change(%{"search" => "Picker"})
      assert has_element?(composer, "[data-audience-group='#{joined.id}']")
      refute has_element?(composer, "[data-audience-group='#{unjoined.id}']")
      refute has_element?(composer, "[data-audience-group='#{readonly.id}']")
      composer |> element("#composer_audience_picker_search_form") |> render_change(%{"search" => "unjoined"})
      assert has_element?(composer, "#composer_audience_picker [role=status]", "No matching joined groups")
      render(view)
    end)
  end

  test "groups without posting permission are neither offered nor selectable by a forged event" do
    account = fake_account!()
    user = fake_user!(account)
    owner = fake_user!()
    group = Bonfire.Classify.Simulate.fake_group!(owner, %{
      name: "Restricted needle collective",
      membership: "on_request",
      visibility: "nonfederated:preview",
      participation: "group_members",
      default_content_visibility: "members:private"
    })

    conn(user: user, account: account)
    |> visit("/feed/local")
    |> PhoenixTest.unwrap(fn view ->
      composer = composer_view(view)
      composer |> element("#composer_audience_picker_search_form") |> render_change(%{"search" => "Restricted needle"})
      refute has_element?(composer, "[data-audience-group='#{group.id}']")
      render_click(composer, "Bonfire.UI.Common.SmartInput:select_audience_group", %{"id" => group.id})
      refute has_element?(composer, "input[name=context_id][value='#{group.id}']")
      render(view)
    end)
  end
end
