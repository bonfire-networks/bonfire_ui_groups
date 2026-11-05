defmodule Bonfire.UI.Groups.Settings.IdentityLive do
  use Bonfire.UI.Common.Web, :stateful_component

  prop category, :any, required: true
  data draft, :map, default: nil

  @doc "Builds the identity form from the current group so reopening settings reflects saved changes."
  def render(assigns) do
    form =
      (assigns.draft ||
         %{
           "name" =>
             e(assigns.category, :profile, :name, nil) ||
               e(assigns.category, :character, :username, nil),
           "summary" => e(assigns.category, :profile, :summary, nil)
         })
      |> to_form(as: :profile)

    assigns
    |> assign(:form, form)
    |> assign(:sensitive?, Bonfire.Classify.Categories.sensitive?(assigns.category))
    |> assign(:hosted_here?, Bonfire.Me.Integration.is_local?(assigns.category))
    |> render_sface()
  end
end
