defmodule Bonfire.UI.Groups.LiveHandlerTest do
  use Bonfire.UI.Social.ConnCase, async: true
  alias Bonfire.Social.Fake
  alias Bonfire.Social.Posts
  alias Bonfire.Social.Follows
  alias Bonfire.Me.Users
  alias Bonfire.Files.Test
  import Bonfire.Common.Enums
  import Bonfire.UI.Me.Integration

  describe "group creation" do
    test "Create a group works" do
      account = fake_account!()
      me = fake_user!(account)
      conn = conn(user: me, account: account)
      next = "/"
      {:ok, view, _html} = live(conn, next)

      view
      |> element("[data-id=create_new_group] div[data-role=open_modal]")
      |> render_click()

      group_name = "Friends"
      {:ok, group_view, html} =
        view
        |> form("#new_group_form", name: group_name, summary: "test description", to_boundaries: ["visible"])
        |> render_submit()
        |> follow_redirect(conn)

        assert html =~ "Created!"
        assert html =~ group_name
    end

    test "If I create an open group, anyone can join" do
      account = fake_account!()
      me = fake_user!(account)
      alice = fake_user!(account)
      name = "Friends"
      description = "test description"
      to_boundaries = ["open"]
      {:ok, group} = Bonfire.Classify.Categories.create(
        me,
        %{category: %{
          name: name,
          description: description,
          to_boundaries: to_boundaries,
          type: :group
        }},
        true
      )
      conn = conn(user: alice, account: account)
      next = "/&#{group.character.username}"
      {:ok, view, _html} = live(conn, next)

      assert render(view) =~ "Join"
      assert view |> has_element?("[data-id=follow]")
      assert view |> element("[data-id=follow]") |> render_click()
      # assert render(view) =~ "joined"
      # assert view |> element("[data-id=follow]") |> render_click() |> has_element?("[data-id=unfollow]")

    end

    test "If I create a visible group, anyone can request to join" do
      account = fake_account!()
      me = fake_user!(account)
      alice = fake_user!(account)
      name = "Friends"
      description = "test description"
      to_boundaries = ["visible"]
      {:ok, group} = Bonfire.Classify.Categories.create(
        me,
        %{category: %{
          name: name,
          description: description,
          to_boundaries: to_boundaries,
          type: :group
        }},
        true
      )
      conn = conn(user: alice, account: account)
      next = "/&#{group.character.username}"
      {:ok, view, _html} = live(conn, next)

      assert render(view) =~ "Request to join"
      assert view |> has_element?("[data-id=follow]")
    end


    test "If I create a private group, a user with the invite can join" do

    end

    test "A private group is not visible in the local feed, even if I am a follower of the group creator" do

    end

    test "I cannot see a private group without an invite" do
      account = fake_account!()
      me = fake_user!(account)
      alice = fake_user!(account)
      name = "Friends"
      description = "test description"
      to_boundaries = ["private"]
      {:ok, group} = Bonfire.Classify.Categories.create(
        me,
        %{category: %{
          name: name,
          description: description,
          to_boundaries: to_boundaries,
          type: :group
        }},
        true
      )
      conn = conn(user: alice, account: account)
      next = "/&#{group.character.username}"
      {:ok, view, _html} = live(conn, next)
      refute render(view) =~ name
    end

    test "If I joined a group, I can leave it" do

    end

    test "If I joined a group, I can see the group activities" do

    end

    test "If I joined a group, I can see the group members" do

    end

    test "If I joined a group, I can see the group admins" do

    end

    test "If I joined a group, I can see the group info (description, creation date, boundary)" do

    end

  end


  describe "Publish in group" do
    test "If I joined a group, I can publish a post into it" do

    end

    test "When I publish into a group, the activity is not visible outside the group" do

    end

    test "When I publish into a group, the activity is visible in the group" do

    end
  end


  describe "General settings" do
    test "Group admin can create group invite links" do

    end

    test "Group admin can see group invite links" do

    end

    test "Group admin can remove group invite links" do

    end

    test "Group admin can see requests to join the group"  do

    end

    test "Group admin can accept requests to join the group" do

    end

    test "Group admin can reject requests to join the group" do

    end


    test "Group admin can see group settings" do

    end

    test "Group admin can edit the group general information" do

    end
  end


  describe "Moderate group" do
    test "Group Admin can remove a post from the group" do

    end

    test "Group Admin can remove a member from the group" do

    end

    test "Group admin can see flagged posts" do

    end

    test "Group admin can see flagged members" do

    end

    test "Group Admin can add other admins" do

    end


    test "Group admin can remove admins" do

    end


    test "Group admin can add more roles and add members to them" do

    end

  end



  describe "Delete group" do

    test "Group admin can archive group" do

    end

    test "Group admin can delete group" do

    end
  end
end
