defmodule Citadel.EmailsTest do
  use Citadel.DataCase, async: true

  alias Citadel.Emails

  describe "workspace_invitation_email/2" do
    test "composes email with correct recipients and subject" do
      owner = generate(user())
      workspace = generate(workspace([], actor: owner))

      invitation =
        generate(workspace_invitation([workspace_id: workspace.id], actor: owner))
        |> Ash.load!([:workspace, :invited_by], authorize?: false)

      accept_url = "https://example.com/invitations/#{invitation.token}"

      email = Emails.workspace_invitation_email(invitation, accept_url)

      assert email.to == [{"", to_string(invitation.email)}]
      assert email.subject =~ workspace.name
      assert email.text_body =~ accept_url
      assert email.html_body =~ accept_url
    end

    test "email body contains workspace name and inviter email" do
      owner = generate(user())
      workspace = generate(workspace([], actor: owner))

      invitation =
        generate(workspace_invitation([workspace_id: workspace.id], actor: owner))
        |> Ash.load!([:workspace, :invited_by], authorize?: false)

      email =
        Emails.workspace_invitation_email(invitation, "https://example.com/invitations/token")

      assert email.text_body =~ workspace.name
      assert email.text_body =~ to_string(owner.email)
      assert email.html_body =~ workspace.name
      assert email.html_body =~ to_string(owner.email)
    end

    test "includes expiration date in email body" do
      owner = generate(user())
      workspace = generate(workspace([], actor: owner))

      invitation =
        generate(workspace_invitation([workspace_id: workspace.id], actor: owner))
        |> Ash.load!([:workspace, :invited_by], authorize?: false)

      email =
        Emails.workspace_invitation_email(invitation, "https://example.com/invitations/token")

      assert email.text_body =~ "expires"
      assert email.html_body =~ "expires"
    end

    test "includes from address" do
      owner = generate(user())
      workspace = generate(workspace([], actor: owner))

      invitation =
        generate(workspace_invitation([workspace_id: workspace.id], actor: owner))
        |> Ash.load!([:workspace, :invited_by], authorize?: false)

      email =
        Emails.workspace_invitation_email(invitation, "https://example.com/invitations/token")

      assert {"Citadel", "noreply@citadel.app"} = email.from
    end
  end
end
