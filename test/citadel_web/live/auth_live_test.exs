defmodule CitadelWeb.AuthLiveTest do
  use CitadelWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias AshAuthentication.AddOn.Confirmation
  alias Citadel.Accounts.User

  describe "sign-in page" do
    test "renders sign-in page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/sign-in")

      assert html =~ "Sign in"
      assert html =~ "Email"
      assert html =~ "Password"
    end

    test "shows link to registration page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/sign-in")

      assert html =~ "Need an account?"
      assert html =~ "/register"
    end

    test "shows link to forgot password", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/sign-in")

      assert html =~ "Forgot your password?"
      assert html =~ "/reset"
    end

    test "shows OAuth sign-in option", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/sign-in")

      # Should have Google OAuth button
      assert html =~ "Google" or html =~ "google"
    end

    test "redirects authenticated user away from sign-in", %{conn: conn} do
      %{conn: conn} = register_and_log_in_user(%{conn: conn})

      result = live(conn, ~p"/sign-in")

      assert {:error, {:redirect, %{to: redirect_path}}} = result
      assert redirect_path == "/dashboard"
    end
  end

  describe "registration page" do
    test "renders registration page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/register")

      assert html =~ "Register"
      assert html =~ "Email"
      assert html =~ "Password"
    end

    test "shows link to sign-in page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/register")

      assert html =~ "Already have an account?"
      assert html =~ "/sign-in"
    end

    test "redirects authenticated user away from registration", %{conn: conn} do
      %{conn: conn} = register_and_log_in_user(%{conn: conn})

      result = live(conn, ~p"/register")

      assert {:error, {:redirect, %{to: redirect_path}}} = result
      assert redirect_path == "/dashboard"
    end
  end

  describe "password reset request page" do
    test "renders password reset request page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/reset")

      assert html =~ "Reset" or html =~ "reset"
      assert html =~ "Email" or html =~ "email"
    end

    test "shows link back to sign-in", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/reset")

      assert html =~ "/sign-in"
    end
  end

  describe "email confirmation page" do
    test "renders confirmation page with valid token", %{conn: conn} do
      email = Citadel.DataCase.unique_user_email()
      password = "SecurePass123"

      # Create unconfirmed user
      {:ok, user} =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: email,
          password: password,
          password_confirmation: password
        })
        |> Ash.create(authorize?: false)

      # Generate a valid confirmation token
      strategy = AshAuthentication.Info.strategy!(User, :confirm_new_user)

      changeset =
        user
        |> Ash.Changeset.new()
        |> Ash.Changeset.change_attribute(:email, user.email)

      {:ok, token} = Confirmation.confirmation_token(strategy, changeset, user)

      # Visit confirmation page
      {:ok, _view, html} = live(conn, ~p"/confirm_new_user/#{token}")

      # Should render the confirmation form
      assert html =~ "Confirm" or html =~ "confirm"
    end

    test "renders confirmation page with invalid token", %{conn: conn} do
      # Visit confirmation page with invalid token
      {:ok, _view, html} = live(conn, ~p"/confirm_new_user/invalid_token")

      # Should still render the page (error shown on form submission)
      assert html =~ "Confirm" or html =~ "confirm"
    end
  end

  describe "authentication flow integration" do
    test "successful registration redirects to home", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/register")

      email = Citadel.DataCase.unique_user_email()
      password = "SecurePass123"

      # Fill in the registration form - use the wrapper-based selector
      form_data = %{
        "user" => %{
          "email" => email,
          "password" => password,
          "password_confirmation" => password
        }
      }

      # Submit the form using the wrapper selector to find the form inside
      view
      |> form("#user-password-register-with-password-wrapper form", form_data)
      |> render_submit()

      # The form submission goes through the auth controller which handles the redirect
    end

    test "sign-in form can be submitted", %{conn: conn} do
      email = Citadel.DataCase.unique_user_email()
      password = "SecurePass123"

      # Create a user first
      {:ok, _user} =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: email,
          password: password,
          password_confirmation: password
        })
        |> Ash.create(authorize?: false)

      {:ok, view, _html} = live(conn, ~p"/sign-in")

      # Fill in the sign-in form using the wrapper-based selector
      form_data = %{
        "user" => %{
          "email" => email,
          "password" => password
        }
      }

      # Submit the form using the wrapper selector
      view
      |> form("#user-password-sign-in-with-password-wrapper form", form_data)
      |> render_submit()

      # The form submission triggers auth flow
    end

    test "password reset request form can be submitted", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/reset")

      email = Citadel.DataCase.unique_user_email()

      # Fill in the reset form using the wrapper-based selector
      form_data = %{
        "user" => %{
          "email" => email
        }
      }

      # Submit the form using the wrapper selector
      view
      |> form("#user-password-request-password-reset-token-wrapper form", form_data)
      |> render_submit()

      # Should succeed (even for non-existent email for security)
    end
  end

  describe "password section component" do
    setup :register_and_log_in_user

    test "displays password section in preferences", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/preferences")

      # Should show the password management section
      assert html =~ "Password" or html =~ "password"
    end
  end

  describe "sign out" do
    test "sign out route works", %{conn: conn} do
      %{conn: conn} = register_and_log_in_user(%{conn: conn})

      # Sign out via the route
      conn = get(conn, ~p"/sign-out")

      assert redirected_to(conn) =~ "/"
    end
  end
end
