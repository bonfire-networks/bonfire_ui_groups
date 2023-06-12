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
        preset_descriptions: %{
          "open" => l("anyone can join and participate"),
          "visible" => l("everyone can browse the group/topics/posts, but only members can post"),
          # "visible"=> l("everyone can browse the group/topics/posts, and request to join")
          "private" => l("only people who are invited can join the group and see its contents")
        },
        sections: [
          timeline: Bonfire.UI.Social.ProfileTimelineLive,
          guest: Bonfire.UI.Groups.GuestLive,
          # private: Bonfire.UI.Social.MessageThreadsLive,
          # posts: Bonfire.UI.Social.ProfilePostsLive,
          discover: Bonfire.UI.Groups.DiscoverGroupsLive,
          followers: Bonfire.UI.Social.ProfileFollowsLive,
          members: Bonfire.UI.Social.ProfileFollowsLive,
          settings: Bonfire.UI.Groups.SettingsLive,
          follow: Bonfire.UI.Me.RemoteInteractionFormLive,
          submitted: Bonfire.UI.Social.ProfileTimelineLive
        ],
        navigation: [
          timeline: l("Timeline"),
          # posts: l("Posts"),
          topics: l("Topics"),
          members: l("Members")
        ],
        network: [],
        settings: [
          sections: [
            general: Bonfire.UI.Groups.Settings.GeneralLive,
            # membership: Bonfire.UI.Groups.Settings.MembershipLive,
            invites: Bonfire.UI.Groups.Settings.InvitesLive,
            boundaries: Bonfire.UI.Groups.Settings.BoundariesLive,
            moderation: Bonfire.UI.Groups.Settings.FlagsLive
          ],
          navigation: [
            general: l("General"),
            members: l("Members"),
            # invites: l("Invites"),
            boundaries: l("Boundaries"),
            moderation: l("Moderation"),
            submitted: l("Mentions")
          ]
        ]
      ]
  end
end
