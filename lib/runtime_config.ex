defmodule Bonfire.UI.Groups.RuntimeConfig do
  use Bonfire.Common.Localise

  @behaviour Bonfire.Common.ConfigModule
  def config_module, do: true

  @doc """
  NOTE: you can override this default config in your app's `runtime.exs`, by placing similarly-named config keys below the `Bonfire.Common.Config.LoadExtensionsConfig.load_configs()` line
  """
  def config do
    import Config

    # config :bonfire_ui_groups,
    #   modularity: :disabled

    config :bonfire, :ui,
      activity_preview: [],
      object_preview: [
        {:group, Bonfire.UI.Groups.Preview.GroupLive}
      ],
      group: [
        preset_descriptions: %{
          "open" => l("anyone can join and participate"),
          "visible" => l("everyone can browse the group/topics/posts, but only members can post"),
          # "visible"=> l("everyone can browse the group/topics/posts, and request to join")
          "private" => l("only people who are invited can join the group and see its contents")
        },
        profile: [
          navigation: [
            nil: l("Timeline"),
            about: l("About")
          ]
        ],
        sections: [
          nil: Bonfire.UI.Social.ProfileTimelineLive,
          guest: Bonfire.UI.Groups.GuestLive,
          about: Bonfire.UI.Groups.AboutLive,
          # private: Bonfire.UI.Messages.MessageThreadsLive,
          # posts: Bonfire.UI.Posts.ProfileBoostsLive,
          discover: Bonfire.UI.Groups.DiscoverGroupsLive,
          followers: Bonfire.UI.Social.Graph.ProfileFollowsLive,
          members: Bonfire.UI.Groups.Settings.MembershipLive,
          settings: Bonfire.UI.Groups.SettingsLive,
          follow: Bonfire.UI.Me.RemoteInteractionFormLive,
          submitted: Bonfire.UI.Social.ProfileTimelineLive
        ],
        navigation: [
          nil: l("Timeline"),
          # posts: l("Posts"),
          topics: l("Topics"),
          members: l("Members")
        ],
        network: [],
        settings: [
          sections: [
            nil: Bonfire.UI.Groups.Settings.GeneralLive,
            members: Bonfire.UI.Groups.Settings.MembershipLive,
            invites: Bonfire.UI.Groups.Settings.InvitesLive,
            # boundaries: Bonfire.UI.Groups.Settings.BoundariesLive,
            moderation: Bonfire.UI.Groups.Settings.FlagsLive
          ],
          navigation: [
            nil: l("Settings"),
            members: l("Members"),
            # invites: l("Invites"),
            # boundaries: l("Boundaries"),
            moderation: l("Moderation")
            # submitted: l("Mentions")
          ]
        ]
      ]
  end
end
