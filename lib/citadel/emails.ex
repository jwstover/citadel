defmodule Citadel.Emails do
  @moduledoc """
  Email composition for Citadel application.
  Uses MJML templates for responsive, cross-client compatible emails.
  """
  import Swoosh.Email

  alias CitadelWeb.Emails.EmailConfirmation, as: EmailConfirmationTemplate
  alias CitadelWeb.Emails.PasswordReset, as: PasswordResetTemplate
  alias CitadelWeb.Emails.WorkspaceInvitation, as: WorkspaceInvitationTemplate

  @from_address {"Citadel", "noreply@citadel.app"}

  @doc """
  Composes an invitation email for a workspace invitation.

  ## Parameters

    * `invitation` - The WorkspaceInvitation struct (must have workspace and invited_by loaded)
    * `accept_url` - The full URL for accepting the invitation
  """
  def workspace_invitation_email(invitation, accept_url) do
    inviter_email = to_string(invitation.invited_by.email)
    workspace_name = invitation.workspace.name
    expires_at = Calendar.strftime(invitation.expires_at, "%B %d, %Y at %I:%M %p UTC")
    app_url = CitadelWeb.Endpoint.url()

    html_body =
      WorkspaceInvitationTemplate.render(
        workspace_name: workspace_name,
        inviter_email: inviter_email,
        accept_url: accept_url,
        expires_at: expires_at,
        app_url: app_url
      )

    new()
    |> to({nil, to_string(invitation.email)})
    |> from(@from_address)
    |> subject("You've been invited to join #{workspace_name}")
    |> html_body(html_body)
    |> text_body(invitation_text_body(workspace_name, inviter_email, accept_url, expires_at))
  end

  defp invitation_text_body(workspace_name, inviter_email, accept_url, expires_at) do
    """
    You've been invited to join #{workspace_name}!

    #{inviter_email} has invited you to collaborate on #{workspace_name} in Citadel.

    Click the link below to accept this invitation:
    #{accept_url}

    This invitation expires on #{expires_at}.

    If you didn't expect this invitation, you can safely ignore this email.
    """
  end

  @doc """
  Composes a password reset email.

  ## Parameters

    * `user` - The User struct
    * `reset_url` - The full URL for resetting the password
  """
  def password_reset_email(user, reset_url) do
    app_url = CitadelWeb.Endpoint.url()

    html_body =
      PasswordResetTemplate.render(
        reset_url: reset_url,
        app_url: app_url
      )

    new()
    |> to({user.name || "", to_string(user.email)})
    |> from(@from_address)
    |> subject("Reset your Citadel password")
    |> html_body(html_body)
    |> text_body(password_reset_text_body(reset_url))
  end

  defp password_reset_text_body(reset_url) do
    """
    Reset your password

    You requested a password reset for your Citadel account.

    Click the link below to set a new password:
    #{reset_url}

    This link expires in 1 hour.

    If you didn't request this reset, you can safely ignore this email.
    """
  end

  @doc """
  Composes an email confirmation email.

  ## Parameters

    * `user` - The User struct
    * `confirm_url` - The full URL for confirming the email address
  """
  def confirmation_email(user, confirm_url) do
    app_url = CitadelWeb.Endpoint.url()

    html_body =
      EmailConfirmationTemplate.render(
        confirm_url: confirm_url,
        app_url: app_url
      )

    new()
    |> to({user.name || "", to_string(user.email)})
    |> from(@from_address)
    |> subject("Confirm your Citadel email address")
    |> html_body(html_body)
    |> text_body(confirmation_text_body(confirm_url))
  end

  defp confirmation_text_body(confirm_url) do
    """
    Confirm your email address

    Welcome to Citadel! Please confirm your email address to complete your registration.

    Click the link below to confirm:
    #{confirm_url}

    If you didn't create an account, you can safely ignore this email.
    """
  end
end
