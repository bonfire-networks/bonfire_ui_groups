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
          posts: Bonfire.UI.Social.ProfilePostsLive,
          discover: Bonfire.UI.Groups.DiscoverGroupsLive,
          # Bonfire.UI.Groups.GroupMembersLive
          members: Bonfire.UI.Social.ProfileFollowsLive
        ],
        navigation: [
          timeline: "Timeline",
          posts: "Posts",
          topics: "Topics",
          members: "Members"
          # private: "private",
        ],
        network: [],
        settings: [
          navigation: [
            general: "General",
            members: "Members",
            invites: "Invites",
            notifications: "Notifications"
          ]
        ]
      ]
  end
end
