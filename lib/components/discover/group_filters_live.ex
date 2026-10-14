defmodule Bonfire.UI.Groups.GroupFiltersLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop selected_tab, :string, default: "discover"
  prop search_term, :string, default: ""
  prop join_filter, :string, default: "all"
  prop origin, :string, default: "all"

  @doc "Builds the shared group view, search, origin and policy form."
  def render(assigns) do
    form =
      to_form(
        %{
          "tab" => assigns.selected_tab,
          "search_term" => assigns.search_term,
          "join_filter" => assigns.join_filter,
          "origin" => assigns.origin
        },
        as: :group_filters
      )

    assigns
    |> assign(:form, form)
    |> render_sface()
  end

  def views,
    do: [{"discover", l("All groups")}, {"joined", l("Joined")}, {"archived", l("Archived")}]

  def origins,
    do: [
      {"all", l("All instances")},
      {"local", l("This instance")},
      {"remote", l("Other instances")}
    ]

  def join_policies,
    do: [
      {"all", l("Any joining policy")},
      {"open", l("Open to join")},
      {"request", l("By request")},
      {"invite", l("Invite only")}
    ]

  @doc "The label of the selected option, which the filter's button shows."
  def selected_label(options, value),
    do: Enum.find_value(options, elem(hd(options), 1), fn {v, label} -> v == value && label end)
end
