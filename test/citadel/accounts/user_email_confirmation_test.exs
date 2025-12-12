defmodule Citadel.Accounts.UserEmailConfirmationTest do
  use Citadel.DataCase, async: true

  alias AshAuthentication.AddOn.Confirmation
  alias Citadel.Accounts.User

  describe "email confirmation flow" do
    test "user is unconfirmed after registration with password" do
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

      assert user.confirmed_at == nil
    end

    test "user can be confirmed with a valid confirmation token" do
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

      assert user.confirmed_at == nil

      # Generate a valid confirmation token using AshAuthentication
      # We need a changeset that shows the email attribute changing
      strategy = AshAuthentication.Info.strategy!(User, :confirm_new_user)

      changeset =
        user
        |> Ash.Changeset.new()
        |> Ash.Changeset.change_attribute(:email, user.email)

      {:ok, token} =
        Confirmation.confirmation_token(
          strategy,
          changeset,
          user
        )

      # Confirm the user using the confirm action from AshAuthentication
      {:ok, confirmed_user} =
        Confirmation.Actions.confirm(
          strategy,
          %{"confirm" => token},
          authorize?: false
        )

      assert confirmed_user.confirmed_at != nil
    end

    test "confirmation fails with invalid token" do
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

      strategy = AshAuthentication.Info.strategy!(User, :confirm_new_user)

      # Try to confirm with an invalid token
      result =
        Confirmation.Actions.confirm(
          strategy,
          %{"confirm" => "invalid_token"},
          authorize?: false
        )

      assert {:error, _} = result

      # User should still be unconfirmed
      {:ok, reloaded_user} = Ash.get(User, user.id, authorize?: false)
      assert reloaded_user.confirmed_at == nil
    end
  end
end
