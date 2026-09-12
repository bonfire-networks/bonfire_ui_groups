defmodule Bonfire.UI.Groups.GroupFiltersLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop selected_tab, :string, default: "discover"
  prop search_term, :string, default: ""
  prop join_filter, :string, default: "all"

  @doc "Builds the shared group view, search and policy form."
  def render(assigns) do
    form = to_form(%{"tab" => assigns.selected_tab, "search_term" => assigns.search_term, "join_filter" => assigns.join_filter}, as: :group_filters)

    assigns
    |> assign(:form, form)
    |> render_sface()
  end
end
