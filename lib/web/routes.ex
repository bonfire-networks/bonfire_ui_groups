defmodule Bonfire.UI.Groups.Web.Routes do
  def declare_routes, do: nil

  defmacro __using__(_) do
    quote do
      # pages anyone can view
      scope "/groups/", Bonfire.UI.Groups.Web do
        pipe_through(:browser)

        live("/explore", ExploreLive)
        live("/test", GroupLive)
      end

      # # pages only guests can view
      # scope "/groups/", Bonfire.UI.Groups.Web do
      #   pipe_through(:browser)
      #   pipe_through(:guest_only)
      # end

      # # pages you need an account to view
      # scope "/groups/", Bonfire.UI.Groups.Web do
      #   pipe_through(:browser)
      #   pipe_through(:account_required)
      # end

      # # pages you need to view as a user
      # scope "/groups/", Bonfire.UI.Groups.Web do
      #   pipe_through(:browser)
      #   pipe_through(:user_required)
      # end

      # # pages only admins can view
      # scope "/groups/admin", Bonfire.UI.Groups.Web do
      #   pipe_through(:browser)
      #   pipe_through(:admin_required)
      # end
    end
  end
end
