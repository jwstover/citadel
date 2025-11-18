defmodule Citadel.Accounts.UserTest do
  use Citadel.DataCase, async: true

  alias Citadel.Accounts

  describe "register_with_google/2" do
    test "creates a user and automatically creates a Personal workspace" do
      email = unique_user_email()

      user_info = %{"email" => email}
      oauth_tokens = %{"access_token" => "fake_token"}

      assert {:ok, user} =
               Accounts.User
               |> Ash.Changeset.for_create(:register_with_google, %{
                 user_info: user_info,
                 oauth_tokens: oauth_tokens
               })
               |> Ash.create(authorize?: false)

      assert to_string(user.email) == email

      # Verify a workspace was created
      workspaces = Accounts.list_workspaces!(actor: user)
      assert length(workspaces) == 1

      workspace = List.first(workspaces)
      assert workspace.name == "Personal"
      assert workspace.owner_id == user.id

      # Verify the user is a member of the workspace
      # Reload workspace with members to check membership
      workspace = Accounts.get_workspace_by_id!(workspace.id, actor: user, load: [:members])
      assert length(workspace.members) == 1
      assert List.first(workspace.members).id == user.id
    end

    test "creates workspace even on first registration" do
      email = unique_user_email()

      user_info = %{"email" => email}
      oauth_tokens = %{"access_token" => "fake_token"}

      # Register user for the first time
      assert {:ok, user} =
               Accounts.User
               |> Ash.Changeset.for_create(:register_with_google, %{
                 user_info: user_info,
                 oauth_tokens: oauth_tokens
               })
               |> Ash.create(authorize?: false)

      # Verify workspace exists
      workspaces = Accounts.list_workspaces!(actor: user)
      assert length(workspaces) == 1
      assert List.first(workspaces).name == "Personal"
    end

    test "does not create duplicate workspace on subsequent sign-ins (upsert)" do
      email = unique_user_email()

      user_info = %{"email" => email}
      oauth_tokens = %{"access_token" => "fake_token"}

      # First registration
      assert {:ok, user1} =
               Accounts.User
               |> Ash.Changeset.for_create(:register_with_google, %{
                 user_info: user_info,
                 oauth_tokens: oauth_tokens
               })
               |> Ash.create(authorize?: false)

      workspaces1 = Accounts.list_workspaces!(actor: user1)
      assert length(workspaces1) == 1

      # Subsequent sign-in with same email (upsert)
      assert {:ok, user2} =
               Accounts.User
               |> Ash.Changeset.for_create(:register_with_google, %{
                 user_info: user_info,
                 oauth_tokens: oauth_tokens
               })
               |> Ash.create(authorize?: false)

      # Should be the same user
      assert user1.id == user2.id

      # Should still have only one workspace
      workspaces2 = Accounts.list_workspaces!(actor: user2)
      assert length(workspaces2) == 1
      assert List.first(workspaces2).id == List.first(workspaces1).id
    end
  end
end
