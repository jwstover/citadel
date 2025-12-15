defmodule Citadel.Accounts.UserPasswordResetTest do
  use Citadel.DataCase, async: true

  alias AshAuthentication.Strategy.Password
  alias Citadel.Accounts.User

  describe "request_password_reset_token/1" do
    test "sends reset email for existing user" do
      email = unique_user_email()
      password = "SecurePass123"

      # Create user
      {:ok, _user} =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: email,
          password: password,
          password_confirmation: password
        })
        |> Ash.create(authorize?: false)

      # Request password reset - this should succeed silently
      result =
        User
        |> Ash.ActionInput.for_action(:request_password_reset_token, %{email: email})
        |> Ash.run_action(authorize?: false)

      assert :ok = result
    end

    test "succeeds silently for non-existent email (security)" do
      # Request password reset for non-existent email
      # Should succeed to prevent email enumeration
      result =
        User
        |> Ash.ActionInput.for_action(:request_password_reset_token, %{
          email: "nonexistent@example.com"
        })
        |> Ash.run_action(authorize?: false)

      assert :ok = result
    end
  end

  describe "reset_password_with_token/2" do
    test "resets password with valid token" do
      email = unique_user_email()
      old_password = "OldPass123"
      new_password = "NewPass456"

      # Create user
      {:ok, user} =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: email,
          password: old_password,
          password_confirmation: old_password
        })
        |> Ash.create(authorize?: false)

      # Generate a reset token
      strategy = AshAuthentication.Info.strategy!(User, :password)
      {:ok, token} = Password.reset_token_for(strategy, user)

      # Reset the password
      {:ok, updated_user} =
        user
        |> Ash.Changeset.for_update(:reset_password_with_token, %{
          reset_token: token,
          password: new_password,
          password_confirmation: new_password
        })
        |> Ash.update(authorize?: false)

      assert updated_user.hashed_password != user.hashed_password

      # Verify user can sign in with new password
      {:ok, signed_in_user} =
        User
        |> Ash.Query.for_read(:sign_in_with_password, %{
          email: email,
          password: new_password
        })
        |> Ash.read_one(authorize?: false)

      assert signed_in_user.id == user.id
    end

    test "rejects invalid reset token" do
      email = unique_user_email()
      password = "SecurePass123"

      # Create user
      {:ok, user} =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: email,
          password: password,
          password_confirmation: password
        })
        |> Ash.create(authorize?: false)

      # Try to reset with invalid token
      result =
        user
        |> Ash.Changeset.for_update(:reset_password_with_token, %{
          reset_token: "invalid_token",
          password: "NewPass456",
          password_confirmation: "NewPass456"
        })
        |> Ash.update(authorize?: false)

      assert {:error, _} = result
    end

    test "validates password complexity on reset" do
      email = unique_user_email()
      old_password = "OldPass123"

      # Create user
      {:ok, user} =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: email,
          password: old_password,
          password_confirmation: old_password
        })
        |> Ash.create(authorize?: false)

      # Generate a reset token
      strategy = AshAuthentication.Info.strategy!(User, :password)
      {:ok, token} = Password.reset_token_for(strategy, user)

      # Try to reset with weak password (no uppercase)
      result =
        user
        |> Ash.Changeset.for_update(:reset_password_with_token, %{
          reset_token: token,
          password: "weakpassword123",
          password_confirmation: "weakpassword123"
        })
        |> Ash.update(authorize?: false)

      assert {:error, _} = result
    end

    test "rejects mismatched password confirmation on reset" do
      email = unique_user_email()
      old_password = "OldPass123"

      # Create user
      {:ok, user} =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: email,
          password: old_password,
          password_confirmation: old_password
        })
        |> Ash.create(authorize?: false)

      # Generate a reset token
      strategy = AshAuthentication.Info.strategy!(User, :password)
      {:ok, token} = Password.reset_token_for(strategy, user)

      # Try to reset with mismatched confirmation
      result =
        user
        |> Ash.Changeset.for_update(:reset_password_with_token, %{
          reset_token: token,
          password: "NewPass456",
          password_confirmation: "DifferentPass789"
        })
        |> Ash.update(authorize?: false)

      assert {:error, _} = result
    end

    test "auto-confirms user on password reset" do
      email = unique_user_email()
      old_password = "OldPass123"
      new_password = "NewPass456"

      # Create unconfirmed user
      {:ok, user} =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: email,
          password: old_password,
          password_confirmation: old_password
        })
        |> Ash.create(authorize?: false)

      # User should be unconfirmed initially
      assert user.confirmed_at == nil

      # Generate a reset token
      strategy = AshAuthentication.Info.strategy!(User, :password)
      {:ok, token} = Password.reset_token_for(strategy, user)

      # Reset the password
      {:ok, updated_user} =
        user
        |> Ash.Changeset.for_update(:reset_password_with_token, %{
          reset_token: token,
          password: new_password,
          password_confirmation: new_password
        })
        |> Ash.update(authorize?: false)

      # User should be confirmed after password reset
      assert updated_user.confirmed_at != nil
    end
  end
end
