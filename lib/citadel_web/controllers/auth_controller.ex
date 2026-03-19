defmodule CitadelWeb.AuthController do
  use CitadelWeb, :controller
  use AshAuthentication.Phoenix.Controller

  require Logger

  def success(conn, activity, user, _token) do
    return_to = get_session(conn, :return_to) || ~p"/"

    {message, redirect_to} =
      case activity do
        {:confirm_new_user, :confirm} ->
          {"Your email address has now been confirmed", return_to}

        {:password, :reset_password_with_token} ->
          {"Your password has successfully been reset", return_to}

        {:password, :register_with_password} ->
          {"Welcome! Please check your email to confirm your account.", ~p"/dashboard"}

        _ ->
          {"You are now signed in", return_to}
      end

    conn
    |> delete_session(:return_to)
    |> store_in_session(user)
    # If your resource has a different name, update the assign name here (i.e :current_admin)
    |> assign(:current_user, user)
    |> put_flash(:info, message)
    |> redirect(to: redirect_to)
  end

  def failure(conn, activity, reason) do
    message =
      case {activity, reason} do
        {_,
         %AshAuthentication.Errors.AuthenticationFailed{
           caused_by: %Ash.Error.Forbidden{
             errors: [%AshAuthentication.Errors.CannotConfirmUnconfirmedUser{}]
           }
         }} ->
          """
          You have already signed in another way, but have not confirmed your account.
          You can confirm your account using the link we sent to you, or by resetting your password.
          """

        err ->
          Logger.error("Failed to authenticate user: #{inspect(err)}")
          "Incorrect email or password"
      end

    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/sign-in")
  end

  def sign_out(conn, _params) do
    return_to = get_session(conn, :return_to) || ~p"/"

    conn
    |> clear_session(:citadel)
    |> put_flash(:info, "You are now signed out")
    |> redirect(to: return_to)
  end
end
