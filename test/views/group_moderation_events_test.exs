defmodule Bonfire.UI.Groups.GroupModerationEventsTest do
  @moduledoc """
  The group page's moderation buttons only show to those who may use them, but the events they send (lock, unlock, ban, unban, rename) can be sent by anyone with a LiveView open. These tests send each event as a member who doesn't moderate the group, as a crafted request would, and check that nothing changed. The moderator's same event is the control: it applies.
  """
  use Bonfire.UI.Groups.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  alias Bonfire.Boundaries.Blocks
  alias Bonfire.Classify.Categories
  alias Bonfire.Classify.Simulate

  setup do
    Process.put(:federating, false)

    creator = fake_user!(fake_account!())
    moderator_account = fake_account!()
    moderator = fake_user!(moderator_account)
    member_account = fake_account!()
    member = fake_user!(member_account)
    author = fake_user!(fake_account!())

    group = Simulate.fake_group!(creator, %{membership: "open"})
    {:ok, _} = Categories.add_moderator(creator, group, id(moderator))
    assert {:ok, _} = Categories.join_group(member, group)
    assert {:ok, _} = Categories.join_group(author, group)
    post = Simulate.fake_post_in_group!(author, group, "<p>Moderated</p>")

    # the member can take part, and does not moderate: the premise of every test below
    assert Bonfire.Boundaries.can?(member, :reply, post), "control: the thread starts out open"
    refute Bonfire.Boundaries.can?(member, :mediate, group), "control: a member isn't a moderator"
    assert Bonfire.Boundaries.can?(moderator, :mediate, group), "control: the moderator is one"

    {:ok,
     moderator: moderator,
     moderator_account: moderator_account,
     member: member,
     member_account: member_account,
     author: author,
     group: group,
     post: post}
  end

  # a refused event may come back as an error flash or end the view: either way the state is what counts
  defp send_event(user, account, group, event, params) do
    {:ok, view, _html} =
      live(conn(user: user, account: account), "/group/#{group.character.username}")

    try do
      render_hook(view, event, params)
    catch
      :exit, _ -> :ended
    end
  end

  defp name_of(group) do
    {:ok, group} = Categories.get(id(group), skip_boundary_check: true)
    group |> repo().maybe_preload(:profile) |> e(:profile, :name, nil)
  end

  describe "lock and unlock" do
    test "a member can't lock a thread in the group, and a moderator can", %{
      moderator: moderator,
      moderator_account: moderator_account,
      member: member,
      member_account: member_account,
      group: group,
      post: post
    } do
      event = "Bonfire.Boundaries.Locking:lock"
      params = %{"id" => id(post), "apply_now" => "true"}

      send_event(member, member_account, group, event, params)

      assert Bonfire.Boundaries.can?(member, :reply, post),
             "a member locked a thread in a group they don't moderate"

      send_event(moderator, moderator_account, group, event, params)

      refute Bonfire.Boundaries.can?(member, :reply, post),
             "control: the moderator's lock applies"
    end

    test "a member can't unlock a thread a moderator locked, and a moderator can", %{
      moderator: moderator,
      moderator_account: moderator_account,
      member: member,
      member_account: member_account,
      group: group,
      post: post
    } do
      send_event(moderator, moderator_account, group, "Bonfire.Boundaries.Locking:lock", %{
        "id" => id(post)
      })

      refute Bonfire.Boundaries.can?(member, :reply, post), "control: the thread is locked"

      send_event(member, member_account, group, "Bonfire.Boundaries.Locking:unlock", %{
        "id" => id(post)
      })

      refute Bonfire.Boundaries.can?(member, :reply, post),
             "a member reopened a thread a moderator closed"

      send_event(moderator, moderator_account, group, "Bonfire.Boundaries.Locking:unlock", %{
        "id" => id(post)
      })

      assert Bonfire.Boundaries.can?(member, :reply, post),
             "control: the moderator's unlock applies"
    end
  end

  describe "ban and unban" do
    defp silenced_in?(author, group),
      do: Blocks.is_blocked?(author, :silence, current_user: group) == true

    test "a member can't ban someone from the group, and a moderator can", %{
      moderator: moderator,
      moderator_account: moderator_account,
      member: member,
      member_account: member_account,
      author: author,
      group: group
    } do
      params = %{"id" => id(author), "scope" => id(group), "type" => "silence"}

      send_event(member, member_account, group, "Bonfire.Boundaries.Blocks:block_scoped", params)

      refute silenced_in?(author, group),
             "a member banned someone from a group they don't moderate"

      send_event(
        moderator,
        moderator_account,
        group,
        "Bonfire.Boundaries.Blocks:block_scoped",
        params
      )

      assert silenced_in?(author, group), "control: the moderator's ban applies"
    end

    test "a member can't lift a ban, and a moderator can", %{
      moderator: moderator,
      moderator_account: moderator_account,
      member: member,
      member_account: member_account,
      author: author,
      group: group
    } do
      params = %{"id" => id(author), "scope" => id(group), "type" => "silence"}

      send_event(
        moderator,
        moderator_account,
        group,
        "Bonfire.Boundaries.Blocks:block_scoped",
        params
      )

      assert silenced_in?(author, group), "control: the ban applied"

      send_event(
        member,
        member_account,
        group,
        "Bonfire.Boundaries.Blocks:unblock_scoped",
        params
      )

      assert silenced_in?(author, group), "a member lifted a ban a moderator placed"

      send_event(
        moderator,
        moderator_account,
        group,
        "Bonfire.Boundaries.Blocks:unblock_scoped",
        params
      )

      refute silenced_in?(author, group), "control: the moderator's unban applies"
    end
  end

  describe "rename" do
    test "a member can't rename the group, and a moderator can", %{
      moderator: moderator,
      moderator_account: moderator_account,
      member: member,
      member_account: member_account,
      group: group
    } do
      before = name_of(group)
      event = "Bonfire.UI.Groups:save_group_identity"

      send_event(member, member_account, group, event, %{"profile" => %{"name" => "Taken over"}})

      assert name_of(group) == before, "a member renamed a group they don't moderate"

      send_event(moderator, moderator_account, group, event, %{
        "profile" => %{"name" => "Renamed by moderator"}
      })

      assert name_of(group) == "Renamed by moderator", "control: the moderator's rename applies"
    end
  end

  # The `unflag` event names whose report to remove (`subject`) and where (`context`), and the handler took the context's moderation as the right to remove anyone's report. Any signed-in user can make a group, which they then moderate, so naming their own group let them delete anyone's report on anything
  describe "unflag" do
    test "a member can't remove someone's report by naming a group of their own, and the post's group moderator can",
         %{
           moderator: moderator,
           moderator_account: moderator_account,
           member: member,
           member_account: member_account,
           group: group,
           post: post
         } do
      reporter = fake_user!(fake_account!())
      assert {:ok, _} = Bonfire.Social.Flags.flag(reporter, post)
      assert Bonfire.Social.Flags.flagged?(reporter, post), "control: reported"

      own_group = Simulate.fake_group!(member)
      assert Bonfire.Boundaries.can?(member, :mediate, own_group), "control: they moderate it"

      event = "Bonfire.Social.Flags:unflag"

      for context <- [id(own_group), id(member)] do
        send_event(member, member_account, group, event, %{
          "id" => id(post),
          "subject" => id(reporter),
          "context" => context
        })

        assert Bonfire.Social.Flags.flagged?(reporter, post),
               "a member removed someone's report, naming #{if context == id(member), do: "themself", else: "a group of their own"}"
      end

      send_event(moderator, moderator_account, group, event, %{
        "id" => id(post),
        "subject" => id(reporter),
        "context" => id(group)
      })

      refute Bonfire.Social.Flags.flagged?(reporter, post),
             "control: the post's group moderator dismisses it"
    end
  end
end
