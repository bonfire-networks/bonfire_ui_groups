defmodule Bonfire.UI.Groups.Settings.MembershipLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop selected_tab, :any, default: nil
  prop category, :any, required: true

  prop user, :map
  prop feed, :list, default: []
  prop moderators, :list, default: []
  prop page_info, :any, default: nil
  prop showing_within, :atom, default: :profile
  prop hide_tabs, :boolean, default: false

  @doc "Avoids listing the same user twice when they are both a moderator and in the members circle."
  def members_excluding_moderators(feed, moderators) do
    mod_ids =
      moderators
      |> Enum.map(&subject_id/1)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    Enum.reject(feed, fn entry ->
      case subject_id(entry) do
        nil -> false
        id -> MapSet.member?(mod_ids, id)
      end
    end)
  end

  def subject_profile(entry),
    do:
      e(entry, :profile, nil) || e(entry, :subject, :profile, nil) ||
        e(entry, :edge, :subject, :profile, nil)

  def subject_character(entry),
    do:
      e(entry, :character, nil) || e(entry, :subject, :character, nil) ||
        e(entry, :edge, :subject, :character, nil)

  defp subject_id(entry), do: id(e(entry, :subject, nil)) || id(entry)
end
