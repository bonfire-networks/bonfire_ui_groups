defmodule Bonfire.UI.Groups.GroupMembersLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop category, :map, required: true
  prop group_return_to, :string, default: "/groups"
  prop feed, :list, default: []
  prop moderators, :list, default: []
  prop page_info, :any, default: nil
  prop member_count, :integer, required: true
  prop member_search, :string, default: ""
  prop member_role, :string, default: "all"

  @doc "Combines the loaded members and moderators into one directory, with moderators first."
  def directory_entries(feed, moderators) do
    moderator_ids = moderators |> Enum.map(&id/1) |> MapSet.new()

    (moderators ++ feed)
    |> Enum.uniq_by(&id/1)
    |> Enum.map(fn person ->
      %{
        person: person,
        id: id(person),
        name:
          e(person, :profile, :name, nil) || e(person, :character, :username, l("Unnamed member")),
        handle: Bonfire.Me.Characters.display_username(person, true),
        moderator?: MapSet.member?(moderator_ids, id(person))
      }
    end)
  end

  @doc "Renders filters against the loaded directory without changing its total."
  def render(assigns) do
    entries = directory_entries(assigns.feed, assigns.moderators)
    search = assigns.member_search |> String.trim() |> String.downcase()

    visible =
      Enum.filter(entries, fn entry ->
        (assigns.member_role != "moderators" or entry.moderator?) and
          String.contains?(String.downcase("#{entry.name} #{entry.handle}"), search)
      end)

    assigns
    |> assign(
      entries: entries,
      visible_entries: visible,
      more?: not is_nil(Bonfire.UI.Common.LoadMoreLive.end_cursor(assigns.page_info)),
      form: to_form(%{"search" => assigns.member_search}, as: :members)
    )
    |> render_sface()
  end
end
