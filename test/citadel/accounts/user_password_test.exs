defmodule Citadel.Accounts.UserPasswordTest do
  use Citadel.DataCase, async: true

  alias Citadel.Accounts
  alias Citadel.Accounts.User

  describe "register_with_password/2" do
    test "creates a user with valid password and automatically creates a Personal workspace" do
      email = unique_user_email()
      password = "SecurePass123"

      assert {:ok, user} =
               User
               |> Ash.Changeset.for_create(:register_with_password, %{
                 email: email,
                 password: password,
                 password_confirmation: password
               })
               |> Ash.create(authorize?: false)

      assert to_string(user.email) == email
      assert user.hashed_password != nil
      assert user.hashed_password != password

      # Verify a workspace was created
      workspaces = Accounts.list_workspaces!(actor: user)
      assert length(workspaces) == 1

      workspace = List.first(workspaces)
      assert workspace.name == "Personal"
      assert workspace.owner_id == user.id
    end

    test "rejects passwords shorter than 8 characters" do
      email = unique_user_email()
      password = "Short1"

      assert {:error, changeset} =
               User
               |> Ash.Changeset.for_create(:register_with_password, %{
                 email: email,
                 password: password,
                 password_confirmation: password
               })
               |> Ash.create(authorize?: false)

      assert %Ash.Error.Invalid{} = changeset
    end

    test "rejects passwords without uppercase letter" do
      email = unique_user_email()
      password = "lowercase123"

      assert {:error, changeset} =
               User
               |> Ash.Changeset.for_create(:register_with_password, %{
                 email: email,
                 password: password,
                 password_confirmation: password
               })
               |> Ash.create(authorize?: false)

      assert %Ash.Error.Invalid{} = changeset
    end

    test "rejects passwords without lowercase letter" do
      email = unique_user_email()
      password = "UPPERCASE123"

      assert {:error, changeset} =
               User
               |> Ash.Changeset.for_create(:register_with_password, %{
                 email: email,
                 password: password,
                 password_confirmation: password
               })
               |> Ash.create(authorize?: false)

      assert %Ash.Error.Invalid{} = changeset
    end

    test "rejects passwords without number" do
      email = unique_user_email()
      password = "NoNumbersHere"

      assert {:error, changeset} =
               User
               |> Ash.Changeset.for_create(:register_with_password, %{
                 email: email,
                 password: password,
                 password_confirmation: password
               })
               |> Ash.create(authorize?: false)

      assert %Ash.Error.Invalid{} = changeset
    end

    test "rejects mismatched password confirmation" do
      email = unique_user_email()

      assert {:error, changeset} =
               User
               |> Ash.Changeset.for_create(:register_with_password, %{
                 email: email,
                 password: "SecurePass123",
                 password_confirmation: "DifferentPass123"
               })
               |> Ash.create(authorize?: false)

      assert %Ash.Error.Invalid{} = changeset
    end

    test "rejects duplicate email" do
      email = unique_user_email()
      password = "SecurePass123"

      # Create first user
      {:ok, _user1} =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: email,
          password: password,
          password_confirmation: password
        })
        |> Ash.create(authorize?: false)

      # Try to create second user with same email
      assert {:error, changeset} =
               User
               |> Ash.Changeset.for_create(:register_with_password, %{
                 email: email,
                 password: password,
                 password_confirmation: password
               })
               |> Ash.create(authorize?: false)

      assert %Ash.Error.Invalid{} = changeset
    end
  end

  describe "set_password/2" do
    test "allows OAuth user to set password" do
      # Create a user without a password (simulating OAuth-only user via OAuth)
      email = unique_user_email()
      user_info = %{"email" => email}
      oauth_tokens = %{"access_token" => "fake_token"}

      {:ok, user} =
        User
        |> Ash.Changeset.for_create(:register_with_google, %{
          user_info: user_info,
          oauth_tokens: oauth_tokens
        })
        |> Ash.create(authorize?: false)

      # Verify user has no password initially
      assert user.hashed_password == nil

      password = "SecurePass123"

      assert {:ok, updated_user} =
               Accounts.set_password(user, password, password, actor: user)

      assert updated_user.hashed_password != nil
      assert updated_user.hashed_password != password
    end

    test "rejects if user already has a password" do
      email = unique_user_email()
      password = "SecurePass123"

      # Create user with password
      {:ok, user} =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: email,
          password: password,
          password_confirmation: password
        })
        |> Ash.create(authorize?: false)

      # Reload the user to ensure hashed_password is available
      {:ok, user} = Ash.get(User, user.id, authorize?: false)

      # Try to set password again
      assert {:error, _} =
               Accounts.set_password(user, "NewPass123", "NewPass123", actor: user)
    end

    test "validates password complexity for set_password" do
      # Create OAuth user without password
      email = unique_user_email()
      user_info = %{"email" => email}
      oauth_tokens = %{"access_token" => "fake_token"}

      {:ok, user} =
        User
        |> Ash.Changeset.for_create(:register_with_google, %{
          user_info: user_info,
          oauth_tokens: oauth_tokens
        })
        |> Ash.create(authorize?: false)

      # Too short
      assert {:error, _} =
               Accounts.set_password(user, "Short1", "Short1", actor: user)

      # No uppercase
      assert {:error, _} =
               Accounts.set_password(user, "lowercase123", "lowercase123", actor: user)

      # No lowercase
      assert {:error, _} =
               Accounts.set_password(user, "UPPERCASE123", "UPPERCASE123", actor: user)

      # No number
      assert {:error, _} =
               Accounts.set_password(user, "NoNumbersHere", "NoNumbersHere", actor: user)
    end
  end

  describe "change_password/2" do
    test "allows user to change password with correct current password" do
      email = unique_user_email()
      old_password = "OldPass123"
      new_password = "NewPass456"

      {:ok, user} =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: email,
          password: old_password,
          password_confirmation: old_password
        })
        |> Ash.create(authorize?: false)

      # Reload to get the full user data
      {:ok, user} = Ash.get(User, user.id, authorize?: false)

      assert {:ok, updated_user} =
               Accounts.change_password(
                 user,
                 old_password,
                 new_password,
                 new_password,
                 authorize?: false
               )

      assert updated_user.hashed_password != user.hashed_password
    end

    test "rejects password change with incorrect current password" do
      email = unique_user_email()
      password = "SecurePass123"

      {:ok, user} =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: email,
          password: password,
          password_confirmation: password
        })
        |> Ash.create(authorize?: false)

      {:ok, user} = Ash.get(User, user.id, authorize?: false)

      assert {:error, _} =
               Accounts.change_password(
                 user,
                 "WrongPassword123",
                 "NewPass456",
                 "NewPass456",
                 authorize?: false
               )
    end
  end
end
