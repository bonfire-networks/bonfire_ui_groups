defmodule Bonfire.UI.Groups.Routes do
  def declare_routes, do: nil

  defmacro __using__(_) do
    quote do
      aliases = ["/group/", "/&"]

      # pages anyone can view
      scope "/", Bonfire.UI.Groups do
        pipe_through(:browser)

        live("/groups", ExploreLive, as: :groups)
        live("/group", ExploreLive)
        live("/&", ExploreLive, as: Bonfire.UI.Groups.GroupLive)

        live_aliases(aliases, "/:alias:id", GroupLive, as: :group)
        live_aliases(aliases, "/:alias:id/follow", GroupLive, :follow, as: :group)
        live_aliases(aliases, "/:alias:id/discover", GroupLive, :discover, as: :group)
        live_aliases(aliases, "/:alias:id/about", GroupLive, :about, as: :group)
      end

      # # pages only guests can view
      # scope "/groups/", Bonfire.UI.Groups do
      #   pipe_through(:browser)
      #   pipe_through(:guest_only)
      # end

      # # pages you need an account to view
      # scope "/groups/", Bonfire.UI.Groups do
      #   pipe_through(:browser)
      #   pipe_through(:account_required)
      # end

      # pages you need to view as a user
      scope "/", Bonfire.UI.Groups do
        pipe_through(:browser)
        pipe_through(:user_required)

        live_aliases(aliases, "/:alias:id/members", GroupLive, :members, as: :group)
        live_aliases(aliases, "/:alias:id/submitted", GroupLive, :submitted, as: :group)
        live_aliases(aliases, "/:alias:id/:tab", GroupLive, as: :group)
        live_aliases(aliases, "/:alias:id/:tab/:tab_id", GroupLive, as: :group)

        live_aliases(aliases, "/:alias:id/settings", GroupLive, :settings, as: :group)
        live_aliases(aliases, "/:alias:id/settings/mentions", GroupLive, :submitted, as: :group)
        live_aliases(aliases, "/:alias:id/settings/membership", GroupLive, :members, as: :group)
      end

      # # pages only admins can view
      # scope "/groups/admin", Bonfire.UI.Groups do
      #   pipe_through(:browser)
      #   pipe_through(:admin_required)
      # end
    end
  end
end
