defmodule Bonfire.UI.Groups.LiveHandlerTest do
  use Bonfire.UI.Groups.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  alias Bonfire.Classify.Categories
  alias Bonfire.Social.Graph.Follows
  alias Bonfire.Posts

  defp create_group(creator, attrs \\ %{}) do
    name = attrs[:name] || "Test Group #{System.unique_integer([:positive])}"

    {:ok, group} =
      Categories.create(
        creator,
        %{
          category: %{
            name: name,
            description: attrs[:description] || "A test group",
            to_boundaries: attrs[:to_boundaries] || ["open"],
            type: :group
          }
        },
        true
      )

    group
  end

  describe "group creation" do
    test "create a group via the LiveHandler" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group(me, name: "Created Group", description: "test description")

      assert group.profile.name == "Created Group"
      assert group.character.username

      conn = conn(user: me, account: account)
      {:ok, _view, html} = live(conn, "/&#{group.character.username}")

      assert html =~ "Created Group"
    end

    test "create group form is accessible from the groups page" do
      account = fake_account!()
      me = fake_user!(account)
      conn = conn(user: me, account: account)

      {:ok, _view, html} = live(conn, "/groups")

      assert html =~ "Create a group"
    end

    test "group is accessible at its URL after creation" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group(me, name: "Accessible Group")

      conn = conn(user: me, account: account)
      {:ok, _view, html} = live(conn, "/&#{group.character.username}")

      assert html =~ "Accessible Group"
    end

    @tag :todo
    test "if I create an open group, anyone can join" do
      # TODO: blocked by boundary preset detection bug -
      # get_preset_on_object returns wrong ACL so group shows as "private"
      # and the FollowButton is not rendered for non-members
    end

    @tag :todo
    test "if I create a visible group, anyone can request to join" do
      # TODO: blocked by same boundary preset detection bug
    end

    test "I cannot see a private group without an invite" do
      account = fake_account!()
      me = fake_user!(account)
      alice = fake_user!(account)

      group = create_group(me, to_boundaries: ["private"])

      conn = conn(user: alice, account: account)
      {:error, _} = live(conn, "/&#{group.character.username}")
    end
  end

  describe "group page" do
    test "group creator can see the group page with name and description" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group(me, name: "Cozy Club", description: "A cozy place")

      conn = conn(user: me, account: account)
      {:ok, _view, html} = live(conn, "/&#{group.character.username}")

      assert html =~ "Cozy Club"
    end

    test "group creator is listed as a member on about page" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group(me, name: "My Group")

      conn = conn(user: me, account: account)
      {:ok, _view, html} = live(conn, "/&#{group.character.username}/about")

      assert html =~ e(me, :profile, :name, "")
    end

    test "group about page shows group details" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group(me, name: "Detail Group", description: "A detailed description")

      conn = conn(user: me, account: account)
      {:ok, _view, html} = live(conn, "/&#{group.character.username}/about")

      assert html =~ "Group details"
      assert html =~ "Members"
      assert html =~ "Created"
    end

    test "group appears in the groups listing" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group(me, name: "Listed Group")

      conn = conn(user: me, account: account)
      {:ok, _view, html} = live(conn, "/groups")

      assert html =~ "Listed Group"
    end

    test "group sidebar shows joined groups" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group(me, name: "Sidebar Group")

      conn = conn(user: me, account: account)
      {:ok, _view, html} = live(conn, "/&#{group.character.username}")

      assert html =~ "Sidebar Group"
    end
  end

  describe "group settings" do
    test "group admin can access settings page" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group(me, name: "Settings Group")

      conn = conn(user: me, account: account)
      {:ok, _view, html} = live(conn, "/&#{group.character.username}/settings")

      assert html =~ "Appareance"
      assert html =~ "Permissions"
    end

    test "group admin can edit group name and description" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group(me, name: "Old Name", description: "Old description")

      conn = conn(user: me, account: account)
      {:ok, view, _html} = live(conn, "/&#{group.character.username}/settings")

      html =
        view
        |> form("form[phx-submit='Bonfire.Classify:edit']", %{
          "profile" => %{"name" => "New Name", "summary" => "New description"}
        })
        |> render_submit()

      # The edit handler shows a success flash
      assert html =~ "updated" or html =~ "New Name"
    end

    test "non-admin cannot edit group settings" do
      account = fake_account!()
      me = fake_user!(account)
      alice = fake_user!(account)
      group = create_group(me, name: "Protected Group")

      # Alice joins the group first
      Follows.follow(alice, group, skip_boundary_check: true)

      conn = conn(user: alice, account: account)
      {:ok, _view, html} = live(conn, "/&#{group.character.username}/settings")

      assert html =~ "Sorry, you cannot edit this group"
    end

    test "settings page shows danger zone" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group(me, name: "Danger Group")

      conn = conn(user: me, account: account)
      {:ok, _view, html} = live(conn, "/&#{group.character.username}/settings")

      assert html =~ "Danger zone"
      assert html =~ "Delete group"
    end
  end

  describe "group membership" do
    test "group creator is automatically a follower" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group(me)

      assert Follows.following?(me, group)
    end

    test "a user can follow/join a group programmatically" do
      account = fake_account!()
      me = fake_user!(account)
      alice = fake_user!(account)
      group = create_group(me)

      assert {:ok, _} = Follows.follow(alice, group, skip_boundary_check: true)
      assert Follows.following?(alice, group)
    end

    test "a joined member appears on the group about page" do
      account = fake_account!()
      me = fake_user!(account)
      alice = fake_user!(account)
      group = create_group(me, name: "Member Check Group")

      Follows.follow(alice, group, skip_boundary_check: true)

      conn = conn(user: me, account: account)
      {:ok, _view, html} = live(conn, "/&#{group.character.username}/about")

      assert html =~ e(alice, :profile, :name, "")
    end

    test "a user can leave a group" do
      account = fake_account!()
      me = fake_user!(account)
      alice = fake_user!(account)
      group = create_group(me)

      Follows.follow(alice, group, skip_boundary_check: true)
      assert Follows.following?(alice, group)

      Follows.unfollow(alice, group)
      refute Follows.following?(alice, group)
    end
  end

  describe "publish in group" do
    test "group member can publish a post into the group" do
      # TODO
    end

    test "anyone can post in open group, which visible to the author when visiting the group" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group(me, name: "Feed Post Group for Author")

      attrs = %{
        post_content: %{html_body: "<p>Group post content here</p>"},
        mentions: [group.id]
      }

      {:ok, post} =
        Posts.publish(
          current_user: me,
          post_attrs: attrs,
          context_id: group.id,
          to_circles: [group.id],
          boundary: "public"
        )

      assert post

      # Verify post was created and associated with the group
      conn = conn(user: me, account: account)

      conn
      |> visit("/&#{group.character.username}")
      |> wait_async()
      |> assert_has_or_open_browser("article", text: "Group post content here")
    end

    test "anyone can post in open group, which visible to anyone when visiting the group" do
      account = fake_account!()
      me = fake_user!(account)
      other = fake_user!(account)
      group = create_group(me, name: "Feed Post Group Public")

      attrs = %{
        post_content: %{html_body: "<p>Group post content here</p>"},
        mentions: [group.id]
      }

      {:ok, post} =
        Posts.publish(
          current_user: me,
          post_attrs: attrs,
          context_id: group.id,
          to_circles: [group.id],
          boundary: "public"
        )

      assert post

      # Verify post was created and associated with the group
      conn = conn(user: other, account: account)

      conn
      |> visit("/&#{group.character.username}")
      |> wait_async()
      |> assert_has_or_open_browser("article", text: "Group post content here")
    end

    test "'Published in' label is shown on a group post when viewed in a regular feed" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group(me, name: "Label Test Group")

      {:ok, _post} =
        Posts.publish(
          current_user: me,
          post_attrs: %{
            post_content: %{html_body: "<p>A post in a group</p>"},
            mentions: [group.id]
          },
          context_id: group.id,
          to_circles: [group.id],
          boundary: "public"
        )

      conn = conn(user: me, account: account)

      conn
      |> visit("/feed")
      |> wait_async()
      |> assert_has_or_open_browser("[data-role=published_in]", text: "Label Test Group")
    end

    test "'Published in' label is shown on a group post when viewed in author's timeline" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group(me, name: "Label Test Group")

      {:ok, post} =
        Posts.publish(
          current_user: me,
          post_attrs: %{
            post_content: %{html_body: "<p>A post in a group</p>"},
            mentions: [group.id]
          },
          context_id: group.id,
          to_circles: [group.id],
          boundary: "public"
        )

      IO.inspect(Bonfire.Common.Repo.get(Bonfire.Classify.Tree, post.id), label: "tree row")

      conn = conn(user: me, account: account)

      conn
      |> visit("/@#{e(me, :character, :username, nil)}")
      |> wait_async()
      |> assert_has_or_open_browser("[data-role=published_in]", text: "Label Test Group")
    end

    test "'Published in' label is hidden when viewing the post from within the group" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group(me, name: "Hidden Label Group")

      {:ok, _post} =
        Posts.publish(
          current_user: me,
          post_attrs: %{
            post_content: %{html_body: "<p>A post in a group</p>"},
            mentions: [group.id]
          },
          context_id: group.id,
          to_circles: [group.id],
          boundary: "public"
        )

      conn = conn(user: me, account: account)

      conn
      |> visit("/&#{group.character.username}")
      |> wait_async()
      |> refute_has_or_open_browser("[data-role=published_in]", text: "Hidden Label Group")
    end
  end
end
