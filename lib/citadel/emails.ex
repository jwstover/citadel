defmodule Citadel.Emails do
  @moduledoc """
  Email composition for Citadel application.
  Uses MJML templates for responsive, cross-client compatible emails.
  """
  import Swoosh.Email

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
end
