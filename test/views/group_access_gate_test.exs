defmodule Bonfire.UI.Groups.GroupAccessGateTest do
  use Bonfire.UI.Groups.ConnCase, async: false
  @moduletag :ui

  doctest Bonfire.UI.Groups.AccessGateLive, import: true

  setup do
    Process.put([:bonfire, :feed_live_update_many_preload_mode], :inline)
    account = fake_account!()
    owner = fake_user!(account)

    group =
      Bonfire.Classify.Simulate.fake_group!(owner, %{
        name: "Preview club",
        membership: "on_request",
        visibility: "nonfederated:preview",
        participation: "group_members",
        default_content_visibility: "members:private"
      })

    post =
      Bonfire.Classify.Simulate.fake_post_in_group!(owner, group, "<p>Restricted discussion</p>")

    %{account: account, owner: owner, group: group, post: post}
  end

  test "guests see the hero and sign-in overlay without a feed", %{group: group} do
    # a guest has no LiveView socket, so the page they get is the static render, which `visit` does not give (it connects a LiveView), and there is no async load to wait for
    # conn()
    # |> visit("/&#{group.character.username}")
    # |> wait_async()
    conn()
    |> get_conn_render("/&#{group.character.username}")
    |> assert_has("h1", text: "Preview club")
    |> assert_has("#group_access_gate a[href^='/login?go=']", text: "Sign in")
    |> refute_has("[data-id=feed]")
    |> refute_has("[data-id=group]", text: "Restricted discussion")
    |> refute_has("#inline_composer_placeholder")
  end

  test "signed-in nonmembers still see the gate without a sign-in action", context do
    visitor = fake_user!(context.account)

    conn(user: visitor, account: context.account)
    |> visit("/&#{context.group.character.username}")
    |> wait_async()
    |> assert_has("#group_access_gate")
    |> refute_has("#group_access_gate a")
    |> refute_has("[data-id=feed]")
    |> refute_has("#inline_composer_placeholder")
  end

  test "members see their feed instead of the gate", context do
    conn(user: context.owner, account: context.account)
    |> visit("/&#{context.group.character.username}")
    |> wait_async()
    |> refute_has("#group_access_gate")
    |> assert_has("[data-id=feed]", text: "Restricted discussion")
  end

  # Whoever may edit the group's settings gets them past the gate, read or not: a group whose members lost their read grant would otherwise lock its own moderators out of the page that could fix it.
  test "settings open past the gate for whoever may update the group, and stay gated for anyone else",
       context do
    group = context.group
    path = "/&#{group.character.username}/settings/boundaries"

    moderator = fake_user!(context.account)
    assert {:ok, _} = Bonfire.Classify.Categories.add_moderator(context.owner, group, moderator)

    conn(user: moderator, account: context.account)
    |> visit(path)
    |> wait_async()
    |> refute_has("#group_access_gate")
    |> assert_has("#group_settings_boundaries_form")

    # may edit and see, but not read: the gate's own case
    editor = fake_user!(context.account)
    {:ok, acl} = Bonfire.Boundaries.Acls.get_or_create_object_custom_acl(group, context.owner)

    Bonfire.Boundaries.Grants.grant(editor.id, acl, [:see, :edit], true,
      current_user: context.owner
    )

    refute Bonfire.Boundaries.can?(editor, :read, group),
           "the control: the editor holds no read, so the page is the preview it was gated for"

    conn(user: editor, account: context.account)
    |> visit(path)
    |> wait_async()
    |> refute_has("#group_access_gate")
    |> assert_has("#group_settings_boundaries_form")

    stranger = fake_user!(context.account)

    conn(user: stranger, account: context.account)
    |> visit(path)
    |> wait_async()
    |> assert_has("#group_access_gate")
    |> refute_has("#group_settings_boundaries_form")
  end

  test "leaving a populated private group immediately gates content while preserving following",
       context do
    Process.put(:federating, false)
    member_account = fake_account!()
    member = fake_user!(member_account)
    group = context.group
    {:ok, %{requested: true}} = Bonfire.Classify.Categories.join_and_follow_group(member, group)

    {:ok, request} =
      Bonfire.Social.Requests.get(member, Bonfire.Boundaries.Verbs.get_id!(:join), group,
        current_user: context.owner
      )

    {:ok, _} = Bonfire.Classify.Categories.accept_join_request(context.owner, request)
    assert {:ok, _} = Bonfire.Posts.read(context.post.id, current_user: member)

    conn(user: member, account: member_account)
    |> visit("/&#{group.character.username}")
    |> wait_async()
    |> assert_has("[data-id=feed]", text: "Restricted discussion")
    |> assert_has("#inline_composer_placeholder")
    |> assert_has("[data-id=group]", text: "2 members")
    |> assert_has("[data-id=group_hero] [data-role=group-hero-status]", text: "Joined")
    |> click_button("#group_hero_leave_#{group.id}", "Leave group")
    |> click_button("#join_btn_#{group.id}-leave", "Leave group")
    |> wait_async()
    |> assert_has("#group_access_gate")
    |> refute_has("[data-id=feed]")
    |> refute_has("[data-id=group]", text: "Restricted discussion")
    |> refute_has("#inline_composer_placeholder")
    # a viewer who only previews the group gets no members pill and no total (the minimal header)
    # |> assert_has("[data-id=group]", text: "1 member")
    |> refute_has("[data-role=group-hero-members]")

    refute Bonfire.Classify.Categories.member?(member, group)
    assert Bonfire.Social.Graph.Follows.following?(member, group)
    assert {:error, :not_found} = Bonfire.Posts.read(context.post.id, current_user: member)
    refute Bonfire.Boundaries.can?(member, :create, group)
    refute Bonfire.Boundaries.can?(member, :reply, context.post)

    conn(user: member, account: member_account)
    |> visit("/&#{group.character.username}")
    |> wait_async()
    |> assert_has("#group_access_gate")
    |> refute_has("#inline_composer_placeholder")
  end

  # A members-private group denies guests `:see` as well as `:read`, unlike the preview club above, so there is no hero a guest is entitled to. They still arrive here: from a pasted link, a remote profile, and the `/pub/group/<id>` redirect, which lands on the `/group/` path. Whatever the page shows them, it must not be an error.
  for path_fun <- [:friendly, :group_path] do
    test "a guest opening a members-private group (#{path_fun}) gets a not-found page, not a crash",
         context do
      group =
        Bonfire.Classify.Simulate.fake_group!(context.owner, %{
          name: "Members only club",
          membership: "invite_only",
          visibility: "members:private",
          participation: "group_members",
          default_content_visibility: "members:private"
        })

      Bonfire.Classify.Simulate.fake_post_in_group!(
        context.owner,
        group,
        "<p>members only talk</p>"
      )

      path =
        case unquote(path_fun) do
          :friendly -> "/&#{group.character.username}"
          :group_path -> Bonfire.Common.URIs.path(group)
        end

      # a guest has no LiveView socket, so the page they get is the static render, which `visit` does not give (it connects a LiveView), and there is no async load to wait for
      # conn()
      # |> visit(path)
      # |> wait_async()
      # `mounted/3` refuses the group by sending the visitor to the not-found page, which `get_conn_render` does not follow: the browser does, so the test fetches the page the redirect names, as the same visitor
      refused = get(conn(), path)
      %URI{path: to_path, query: to_query} = URI.parse(redirected_to(refused))

      refused
      |> recycle()
      |> get_conn_render(if(to_query, do: "#{to_path}?#{to_query}", else: to_path))
      # the not-found page, reached on purpose: `mounted/3` refuses a group this visitor may not see, and says so
      |> assert_has("#error-headline", text: "Not found")
      # not the crash `GroupLive.mount/3` used to hit by reading a `:category` that was never assigned
      |> refute_has("#error-headline", text: "unexpected")
      |> refute_has("[data-id=feed]")
      |> refute_has("[data-id=group]", text: "members only talk")
    end
  end

  test "a restricted post default does not gate a readable group", context do
    group =
      Bonfire.Classify.Simulate.fake_group!(context.owner, %{
        name: "Readable group",
        visibility: "nonfederated",
        default_content_visibility: "local"
      })

    # a guest has no LiveView socket, so the page they get is the static render, which `visit` does not give (it connects a LiveView), and there is no async load to wait for
    # conn()
    # |> visit("/&#{group.character.username}")
    # |> wait_async()
    conn()
    |> get_conn_render("/&#{group.character.username}")
    |> refute_has("#group_access_gate")
    |> refute_has("[data-role=category_preview]")
  end
end
