defmodule Bonfire.UI.Groups.RuntimeConfig do
  use Bonfire.Common.Localise
  import Bonfire.UI.Common.Modularity.DeclareHelpers

  @behaviour Bonfire.Common.ConfigModule
  def config_module, do: true

  declare_settings(:select, l("Who can create groups"),
    keys: [Bonfire.UI.Groups, :create_groups],
    options: [
      everyone: l("Everyone"),
      admins: l("Admins only")
    ],
    default_value: :everyone,
    description: l("Control who is allowed to create new groups on this instance"),
    scope: :instance
  )

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
          topics: Bonfire.UI.Groups.DiscoverGroupsLive,
          # private: Bonfire.UI.Messages.MessageThreadsLive,
          # posts: Bonfire.UI.Posts.ProfileBoostsLive,
          discover: Bonfire.UI.Groups.DiscoverGroupsLive,
          followers: Bonfire.UI.Social.Graph.ProfileFollowsLive,
          members: Bonfire.UI.Groups.GroupMembersLive,
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
            boundaries: Bonfire.UI.Groups.Settings.BoundariesLive,
            rules: Bonfire.UI.Groups.Settings.DetailLive,
            instance: Bonfire.UI.Groups.Settings.DetailLive,
            archive: Bonfire.UI.Groups.Settings.DetailLive,
            moderators: Bonfire.UI.Groups.Settings.DetailLive,
            moderation: Bonfire.UI.Groups.Settings.ModerationLive
          ],
          # Each page's title, and the overview's rows linking to it (`Settings.GeneralLive`), in order. An entry with a `group` is rendered in that section of the overview (`:people`, `:management`, `:admin`, `:danger`), as a row linking to the page, or as its `component` instead. `description` and `value` may be a function of the overview's assigns, for what has to be worked out per group. A row shows only if its `module` is enabled and the viewer `can` do the verb on the object (`:group` meaning the group). A plain string is a title alone, which extensions may still configure.
          navigation: [
            nil: %{title: l("Group settings")},
            members: %{title: l("Members")},
            # invites: %{title: l("Invites")},
            people: %{group: :people, component: Bonfire.UI.Groups.Settings.PeopleLive},
            boundaries: %{
              title: l("Access & participation"),
              group: :management,
              id: "group_settings_access_link",
              icon: "ph:shield-check",
              description: &Bonfire.UI.Groups.Settings.GeneralLive.membership_label/1,
              value: &Bonfire.UI.Groups.Settings.GeneralLive.visibility_label/1
            },
            rules: %{
              title: l("Community rules"),
              group: :management,
              id: "group_settings_rules_link",
              icon: "ph:book-open",
              description: l("Guidelines members agree to when joining"),
              module: Bonfire.CommunityRules.Web.RulesBuilderLive
            },
            moderation: %{
              title: l("Moderation"),
              group: :management,
              id: "group_settings_moderation_link",
              icon: "ph:flag-duotone",
              description: l("Reports on what's posted in the group"),
              can: {:mediate, :group}
            },
            instance: %{
              title: l("Instance settings"),
              group: :admin,
              id: "group_settings_instance_link",
              icon: "ph:hard-drives",
              description: l("Automatically add new users"),
              value: &Bonfire.UI.Groups.Settings.GeneralLive.auto_join_label/1,
              can: {:configure, :instance}
            },
            archive: %{
              title: l("Archive group"),
              group: :danger,
              id: "group_settings_archive_link",
              icon: "ph:archive",
              description: l("You can restore the group later")
            },
            moderators: %{title: l("Manage moderators")}
            # submitted: %{title: l("Mentions")}
          ]
        ]
      ]
  end
end
