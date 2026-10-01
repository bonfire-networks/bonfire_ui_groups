defmodule Bonfire.UI.Groups.WidgetGroupsCarouselLive do
  @moduledoc """
  A horizontal carousel of compact group cards, showcasing the groups guests can see on the guest homepage board. Lists them via the same boundary-checked query as the groups directory, and renders nothing when there are none.
  """
  use Bonfire.UI.Common.Web, :stateful_component

  alias Bonfire.Common.Cache

  prop title, :string, default: nil
  prop subtitle, :string, default: nil

  @limit 12
  # guests all see the same list, so it's cached briefly like the other guest-page loaders; new groups show up within this window
  @guest_cache_ttl 1_000 * 60 * 10

  def update(assigns, socket) do
    socket = assign(socket, assigns)
    {groups, previews} = list_groups(current_user(assigns(socket)))

    {:ok, assign(socket, groups: groups, previews: previews)}
  end

  defp list_groups(nil), do: list_guest_groups()

  @doc "The groups guests can see, with card previews, cached for all guests. Pass the standard `:cache` opt (`cache: :reset`) to bust it."
  def list_guest_groups(opts \\ []) do
    Cache.maybe_apply_cached(
      &Bonfire.UI.Groups.ExploreLive.list_groups_with_previews/2,
      [nil, [limit: @limit, topics: false]],
      Keyword.put_new(opts, :expire, @guest_cache_ttl)
    )
  end

  defp list_groups(current_user),
    do:
      Bonfire.UI.Groups.ExploreLive.list_groups_with_previews(current_user,
        limit: @limit,
        topics: false
      )
end
