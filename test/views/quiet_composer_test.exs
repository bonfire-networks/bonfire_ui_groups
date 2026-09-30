defmodule Bonfire.UI.Groups.QuietComposerTest do
  use Bonfire.UI.Groups.ConnCase, async: false
  @moduletag :ui

  setup do
    account = fake_account!()
    user = fake_user!(account)
    {:ok, conn: conn(user: user, account: account)}
  end

  test "personal posts keep type and audience in the header and publishing tools in the footer", %{conn: conn} do
    conn
    |> visit("/feed/local")
    |> PhoenixTest.unwrap(fn view ->
      composer = composer_view(view)
      assert has_element?(composer, "#composer_audience_picker_trigger", "Your profile")
      assert has_element?(composer, "#composer_visibility_picker_trigger", "Public")
      refute has_element?(composer, "#composer_audience_picker [data-audience-preset]")
      assert has_element?(composer, "#composer_resize_handle[role=separator][tabindex='0'][aria-label='Resize composer']")
      assert has_element?(composer, "#composer_type_chooser_trigger", "Create post")
      assert has_element?(composer, "#smart_input_post_title:not(.hidden) input[placeholder='Add a title (optional)']")
      refute has_element?(composer, "#smart_input_post_title input[required]")
      refute has_element?(composer, "#title_btn")
      assert has_element?(composer, "#composer_publish_controls #language_dropdown")
      assert has_element?(composer, "#smart_input_more_options #discard_composer")
      refute has_element?(composer, "header #discard_composer")
      refute has_element?(composer, "#composer_publish_controls #composer_type_chooser")
      assert has_element?(composer, "#composer_header_actions > #composer_author:first-child")
      assert has_element?(composer, "#expand_composer_button[aria-label='Expand composer']")
      assert has_element?(composer, "#minimize_composer_button[aria-label='Minimise composer, keep draft']")
      refute has_element?(composer, "#close_composer_button")
      render(view)
    end)
  end

  test "policy controls are a labelled group that includes the custom boundaries editor", %{conn: conn} do
    conn
    |> visit("/feed/local")
    |> PhoenixTest.unwrap(fn view ->
      composer = composer_view(view)
      assert has_element?(composer, "#composer_policy_controls[role=group][aria-label='Audience and permissions'] #composer_audience_picker")
      assert has_element?(composer, "#composer_policy_controls #define_permissions button[aria-label='Custom boundaries']")
      render(view)
    end)
  end

  test "personal audience and permission panels reuse and retain the boundary editor state", %{conn: conn} do
    conn
    |> visit("/feed/local")
    |> PhoenixTest.unwrap(fn view ->
      composer = composer_view(view)
      composer |> element("#define_permissions button[data-role=open_modal]") |> render_click()
      assert has_element?(composer, "#customize_boundary_live [data-role=action_toggle_reply]")
      assert has_element?(composer, "[data-role=permissions_audience_summary]", "Public")
      assert has_element?(composer, "[data-role=permission_interactions] [data-role=action_toggle_reply]")
      assert has_element?(composer, "[data-role=permission_interactions] [data-role=action_toggle_quote]")
      assert has_element?(composer, "[data-role=permission_reading] [data-role=action_toggle_read]")
      refute has_element?(composer, "#customize_boundary_live_general_access_list")
      assert has_element?(composer, "#customize_boundary_live [data-role=save_boundary]", "Done")

      composer |> element("#customize_boundary_live [data-role=action_toggle_reply]") |> render_click()
      refute has_element?(composer, "#customize_boundary_live [data-role=action_toggle_reply][checked]")
      assert has_element?(composer, "[data-role=action_exceptions_reply]", "Allow exceptions")
      composer |> element("#customize_boundary_live [data-role=save_boundary]") |> render_click()
      open_menu(composer, "composer_visibility_picker")
      composer |> element("#composer_visibility_picker_search_form") |> render_change(%{"search" => "Public"})
      assert has_element?(composer, "[data-audience-preset=public]")
      composer |> element("#define_permissions button[data-role=open_modal]") |> render_click()
      assert has_element?(composer, "#customize_boundary_live [data-role=action_toggle_reply]")
      refute has_element?(composer, "#customize_boundary_live [data-role=action_toggle_reply][checked]")
      composer |> element("#customize_boundary_live [data-role=action_toggle_read]") |> render_click()
      assert has_element?(composer, "#composer_visibility_picker_trigger", "Custom audience")
      render(view)
    end)
  end

  test "direct messages get the encryption notice instead of audience controls", %{conn: conn} do
    conn
    |> visit("/feed/local")
    |> PhoenixTest.unwrap(fn view ->
      composer = composer_view(view)
      assert has_element?(composer, "#composer_visibility_picker")

      # how the messages page opens its composer (`open_dm_composer/2`)
      render_click(composer, "Bonfire.UI.Common.SmartInput:select_smart_input", %{
        "opts" => Jason.encode!(%{create_object_type: "message"})
      })

      assert has_element?(composer, "#composer_policy_controls", "Not encrypted")
      refute has_element?(composer, "#composer_audience_picker")
      refute has_element?(composer, "#composer_visibility_picker")
      refute has_element?(composer, "#composer_group_visibility")
      refute has_element?(composer, "#composer_reply_visibility")
      refute has_element?(composer, "#define_permissions")
      render(view)
    end)
  end

  test "locked audience permissions explain why quick controls are unavailable", %{conn: conn} do
    conn
    |> visit("/feed/local")
    |> PhoenixTest.unwrap(fn view ->
      composer = composer_view(view)
      open_menu(composer, "composer_visibility_picker")
      composer |> element("[data-audience-preset=mentions]") |> render_click()
      composer |> element("#define_permissions button[data-role=open_modal]") |> render_click()
      assert has_element?(composer, "[data-role=permissions_locked_notice]", "This audience controls access through its recipients")
      for action <- ~w(read reply quote) do
        assert has_element?(composer, "[data-role=action_toggle_#{action}][disabled]")
      end
      assert has_element?(composer, "[data-role=toggle_advanced_permissions]")
      render(view)
    end)
  end

  test "messages retain the encryption notice and Send without type or scheduling controls", %{conn: conn} do
    conn
    |> visit("/feed/local")
    |> PhoenixTest.unwrap(fn view ->
      composer = composer_view(view)
      render_click(composer, "Bonfire.UI.Common.SmartInput:select_smart_input", %{
        "opts" => Jason.encode!(%{create_object_type: :message, open: true})
      })
      assert render(composer) =~ "Not encrypted"
      assert has_element?(composer, "#submit_btn", "Send")
      refute has_element?(composer, "#composer_type_chooser")
      refute has_element?(composer, "#scheduled_at_btn")
      assert has_element?(composer, "#discard_composer")
      render(view)
    end)
  end
end
