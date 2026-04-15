defmodule Bonfire.UI.Groups.LiveHandlerTest do
  use Bonfire.UI.Groups.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  alias Bonfire.Classify.Categories

  defp post_in_group(session, content, group_id) do
    params = %{
      "post" => %{"post_content" => %{"html_body" => content}},
      "context_id" => group_id,
      "to_circles" => [group_id]
    }

    session
    |> click_button("[data-role=composer_button]", "Write in group")
    |> PhoenixTest.unwrap(fn view ->
      view
      |> Phoenix.LiveViewTest.element("#smart_input_form")
      |> Phoenix.LiveViewTest.render_submit(params)
    end)
  end

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

    test "I cannot see a private group without an invite" do
      account = fake_account!()
      me = fake_user!(account)
      alice = fake_user!(account)

      group = create_group(me, to_boundaries: ["private"])

      conn = conn(user: alice, account: account)
      {:error, _} = live(conn, "/&#{group.character.username}")
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

      {:ok, _} = Categories.join_group(alice, group)

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
    test "if I create a visible group, anyone can request to join" do
      account = fake_account!()
      me = fake_user!(account)
      alice = fake_user!(account)
      group = create_group(me, name: "Visible Group", to_boundaries: ["visible"])

      conn(user: alice, account: account)
      |> visit("/&#{group.character.username}/about")
      |> wait_async()
      |> assert_has("[phx-value-id='#{group.id}']", text: "Request to join")
      |> click_link("[phx-value-id='#{group.id}']", "Request to join")
      |> wait_async()
      |> assert_has("[phx-value-id='#{group.id}']", text: "Requested")

      refute Categories.member?(alice, group)
    end

    test "non-member sees 'Join group' button on open group about page, and after joining, user sees 'Joined' button, and after leaving, user sees 'Join group' button again" do
      account = fake_account!()
      me = fake_user!(account)
      alice = fake_user!(account)
      group = create_group(me, name: "Join Flow Group")

      conn = conn(user: alice, account: account)

      conn
      |> visit("/&#{group.character.username}/about")
      |> wait_async()
      |> assert_has("[phx-value-id='#{group.id}']", text: "Join group")
      |> click_link("[phx-value-id='#{group.id}']", "Join group")
      |> wait_async()
      |> assert_has("[phx-value-id='#{group.id}']", text: "Joined")
      |> click_link("[phx-value-id='#{group.id}']", "Joined")
      |> wait_async()
      |> assert_has("[phx-value-id='#{group.id}']", text: "Join group")
    end

    test "group creator is automatically a follower and member, and sees disabled 'Joined' button" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group(me, name: "Creator Button Group")

      conn = conn(user: me, account: account)

      conn
      |> visit("/&#{group.character.username}/about")
      |> wait_async()
      |> assert_has(".btn-disabled")
      |> assert_has("[phx-value-id='#{group.id}']", text: "Joined")
    end

    test "a joined member appears on the group about page" do
      account = fake_account!()
      me = fake_user!(account)
      alice = fake_user!(account)
      group = create_group(me, name: "Member Check Group")

      conn(user: alice, account: account)
      |> visit("/&#{group.character.username}/about")
      |> wait_async()
      |> click_link("[phx-value-id='#{group.id}']", "Join group")
      |> wait_async()

      conn(user: me, account: account)
      |> visit("/&#{group.character.username}/about")
      |> wait_async()
      |> assert_has("*", text: e(alice, :profile, :name, ""))
    end
  end

  describe "publish in group" do
    test "anyone can post in open group, which visible to the author when visiting the group" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group(me, name: "Feed Post Group for Author")

      conn(user: me, account: account)
      |> visit("/&#{group.character.username}")
      |> wait_async()
      |> post_in_group("<p>Group post content here</p>", group.id)

      conn(user: me, account: account)
      |> visit("/&#{group.character.username}")
      |> wait_async()
      |> assert_has_or_open_browser("article", text: "Group post content here")
    end

    @tag :fixme
    test "group member can publish a post into closed group, visible only to other members" do
      account = fake_account!()
      me = fake_user!(account)
      alice = fake_user!(account)
      bob = fake_user!(account)
      group = create_group(me, name: "Closed Group", to_boundaries: ["private"])

      {:ok, _} = Categories.join_group(alice, group, skip_boundary_check: true)

      conn(user: me, account: account)
      |> visit("/&#{group.character.username}")
      |> wait_async()
      |> post_in_group("<p>Secret group post</p>", group.id)

      # member can see the post
      conn(user: alice, account: account)
      |> visit("/&#{group.character.username}")
      |> wait_async()
      |> assert_has_or_open_browser("article", text: "Secret group post")

      # non-member cannot see the post
      conn(user: bob, account: account)
      |> visit("/&#{group.character.username}")
      |> wait_async()
      |> refute_has_or_open_browser("article", text: "Secret group post")
    end

    test "anyone can post in open group, which visible to anyone when visiting the group" do
      account = fake_account!()
      me = fake_user!(account)
      other = fake_user!(account)
      group = create_group(me, name: "Feed Post Group Public")

      conn(user: me, account: account)
      |> visit("/&#{group.character.username}")
      |> wait_async()
      |> post_in_group("<p>Group post content here</p>", group.id)

      conn(user: other, account: account)
      |> visit("/&#{group.character.username}")
      |> wait_async()
      |> assert_has_or_open_browser("article", text: "Group post content here")
    end

    test "'Published in' label is shown on a group post when viewed in a regular feed" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group(me, name: "Label Test Group")

      conn(user: me, account: account)
      |> visit("/&#{group.character.username}")
      |> wait_async()
      |> post_in_group("<p>A post in a group</p>", group.id)

      conn(user: me, account: account)
      |> visit("/feed")
      |> wait_async()
      |> assert_has_or_open_browser("[data-role=published_in]", text: "Label Test Group")
    end

    test "'Published in' label is shown on a group post when viewed in author's timeline" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group(me, name: "Label Test Group")

      conn(user: me, account: account)
      |> visit("/&#{group.character.username}")
      |> wait_async()
      |> post_in_group("<p>A post in a group</p>", group.id)

      conn(user: me, account: account)
      |> visit("/@#{e(me, :character, :username, nil)}")
      |> wait_async()
      |> assert_has_or_open_browser("[data-role=published_in]", text: "Label Test Group")
    end

    test "'Published in' label is hidden when viewing the post from within the group" do
      account = fake_account!()
      me = fake_user!(account)
      group = create_group(me, name: "Hidden Label Group")

      conn(user: me, account: account)
      |> visit("/&#{group.character.username}")
      |> wait_async()
      |> post_in_group("<p>A post in a group</p>", group.id)
      |> refute_has_or_open_browser("[data-role=published_in]", text: "Hidden Label Group")
    end
  end
end
