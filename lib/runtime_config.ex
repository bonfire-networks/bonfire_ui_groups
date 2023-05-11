defmodule Bonfire.UI.Groups.RuntimeConfig do
  use Bonfire.Common.Localise

  @behaviour Bonfire.Common.ConfigModule
  def config_module, do: true

  @doc """
  NOTE: you can override this default config in your app's `runtime.exs`, by placing similarly-named config keys below the `Bonfire.Common.Config.LoadExtensionsConfig.load_configs()` line
  """
  def config do
    import Config

    config :bonfire_ui_groups,
      disabled: false

    config :bonfire, :ui,
      group: [
        sections: [
          timeline: Bonfire.UI.Social.ProfileTimelineLive,
          # private: Bonfire.UI.Social.MessageThreadsLive,
          # posts: Bonfire.UI.Social.ProfilePostsLive,
          discover: Bonfire.UI.Groups.DiscoverGroupsLive,
          # Bonfire.UI.Groups.GroupMembersLive
          members: Bonfire.UI.Social.ProfileFollowsLive,
          settings: Bonfire.UI.Groups.SettingsLive,
          follow: Bonfire.UI.Me.RemoteInteractionFormLive
        ],
        navigation: [
          timeline: l("Timeline"),
          posts: l("Posts"),
          topics: l("Topics"),
          members: l("Members")
        ],
        network: [],
        settings: [
          sections: [
            general: Bonfire.UI.Groups.Settings.GeneralLive,
            membership: Bonfire.UI.Groups.Settings.MembershipLive,
            notifications: Bonfire.UI.Groups.Settings.NotificationsLive,
            invites: Bonfire.UI.Groups.Settings.InvitesLive
          ],
          navigation: [
            general: l("General"),
            membership: l("Members"),
            notifications: l("Notifications"),
            invites: l("Invites")
          ]
        ]
      ]
  end
end
