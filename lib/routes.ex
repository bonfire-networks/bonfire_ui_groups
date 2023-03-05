defmodule Bonfire.UI.Groups.Routes do
  def declare_routes, do: nil

  defmacro __using__(_) do
    quote do
      # pages anyone can view
      scope "/group/", Bonfire.UI.Groups do
        pipe_through(:browser)

        live("/:id", GroupLive, as: :group)
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

        live("/groups", ExploreLive, as: :group)
        live("/group", ExploreLive)
        live("/group", ExploreLive, as: Bonfire.UI.Groups.GroupLive)
        live("/group/:id/settings", GroupLive, :settings, as: :group)
        live("/group/:id/discover", GroupLive, :discover, as: :group)
        live("/group/:id/members", GroupLive, :members, as: :group)
        live("/group/:id/submitted", GroupLive, :submitted, as: :group)
        live("/group/:id/:tab", GroupLive, as: :group)
        live("/group/:id/:tab/:tab_id", GroupLive, as: :group)
      end

      # # pages only admins can view
      # scope "/groups/admin", Bonfire.UI.Groups do
      #   pipe_through(:browser)
      #   pipe_through(:admin_required)
      # end
    end
  end
end
