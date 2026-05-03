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

  @doc "Returns members not already shown as moderators (compared by id, unwrapping :subject if needed)."
  def members_excluding_moderators(feed, moderators) do
    mod_ids =
      moderators
      |> Enum.map(&entry_id/1)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    Enum.reject(feed, fn entry ->
      case entry_id(entry) do
        nil -> false
        id -> MapSet.member?(mod_ids, id)
      end
    end)
  end

  defp entry_id(entry), do: id(e(entry, :subject, nil)) || id(entry)
end
