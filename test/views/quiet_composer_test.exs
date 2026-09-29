defmodule Bonfire.UI.Groups.QuietComposerTest do
  use Bonfire.UI.Groups.ConnCase, async: false
  @moduletag :ui

  setup do
    account = fake_account!()
    user = fake_user!(account)
    {:ok, conn: conn(user: user, account: account)}
  end

  test "personal posts keep audience editing in the header and creation tools in the footer", %{conn: conn} do
    conn
    |> visit("/feed/local")
    |> PhoenixTest.unwrap(fn view ->
      composer = composer_view(view)
      assert has_element?(composer, "header #define_boundary")
      assert has_element?(composer, "#composer_publish_controls #composer_type_chooser")
      assert has_element?(composer, "#composer_publish_controls #language_dropdown")
      assert has_element?(composer, "#smart_input_more_options #discard_composer")
      refute has_element?(composer, "header #discard_composer")
      assert has_element?(composer, "#minimize_composer_button[aria-label='Close composer, keep draft']")
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
