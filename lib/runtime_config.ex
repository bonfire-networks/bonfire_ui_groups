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
      groups: [
        sections: [
          timeline: Bonfire.UI.Social.ProfileTimelineLive,
          # private: Bonfire.UI.Social.MessageThreadsLive,
          posts: Bonfire.UI.Social.ProfilePostsLive,
          topics: Bonfire.UI.Topics.TopicsLive,
          members: Bonfire.UI.Group.GroupMembersLive
        ],
        navigation: [
          timeline: "Timeline",
          posts: "Posts",
          topics: "Topics",
          members: "Members"
          # private: "private",
        ],
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
