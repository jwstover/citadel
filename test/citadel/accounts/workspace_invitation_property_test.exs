defmodule Citadel.Accounts.WorkspaceInvitationPropertyTest do
  @moduledoc """
  Property-based tests for workspace invitation security and correctness.

  These tests verify:
  - Token uniqueness across all invitations
  - Token security properties (length, entropy, URL-safety)
  - Expiration logic edge cases
  - Invitation state transitions
  """
  use Citadel.DataCase, async: true

  alias Citadel.Accounts

  describe "invitation token uniqueness properties" do
    property "invitation tokens are globally unique across multiple invitations" do
      check all(invitation_count <- integer(2..20)) do
        owner = generate(user())
        workspace = generate(workspace([], actor: owner))

        # Generate multiple invitations
        invitations =
          Enum.map(1..invitation_count, fn _ ->
            generate(
              workspace_invitation(
                [workspace_id: workspace.id],
                actor: owner
              )
            )
          end)

        tokens = Enum.map(invitations, & &1.token)

        # All tokens must be unique
        assert length(Enum.uniq(tokens)) == length(tokens),
               "Found duplicate tokens in #{invitation_count} invitations"
      end
    end

    property "tokens from different workspaces are also unique" do
      check all(workspace_count <- integer(2..5)) do
        # Create multiple workspaces, each with invitations
        all_tokens =
          for _ <- 1..workspace_count do
            owner = generate(user())
            workspace = generate(workspace([], actor: owner))

            invitation =
              generate(
                workspace_invitation(
                  [
                    workspace_id: workspace.id
                  ],
                  actor: owner
                )
              )

            invitation.token
          end

        # Tokens across workspaces must be unique
        assert length(Enum.uniq(all_tokens)) == length(all_tokens)
      end
    end
  end

  describe "invitation token security properties" do
    property "tokens always have sufficient length for security" do
      check all(_ <- integer(1..25)) do
        owner = generate(user())
        workspace = generate(workspace([], actor: owner))

        invitation =
          generate(
            workspace_invitation(
              [
                workspace_id: workspace.id
              ],
              actor: owner
            )
          )

        # Token should be at least 32 characters for good entropy
        assert String.length(invitation.token) >= 32,
               "Token too short: #{String.length(invitation.token)} chars"
      end
    end

    property "tokens are always URL-safe (no special encoding needed)" do
      check all(_ <- integer(1..25)) do
        owner = generate(user())
        workspace = generate(workspace([], actor: owner))

        invitation =
          generate(
            workspace_invitation(
              [
                workspace_id: workspace.id
              ],
              actor: owner
            )
          )

        # Token should only contain URL-safe characters
        assert invitation.token =~ ~r/^[A-Za-z0-9_-]+$/,
               "Token contains non-URL-safe characters"
      end
    end

    property "tokens are not predictable or sequential" do
      check all(_ <- integer(1..50)) do
        owner = generate(user())
        workspace = generate(workspace([], actor: owner))

        # Generate two consecutive invitations
        inv1 =
          generate(
            workspace_invitation(
              [
                workspace_id: workspace.id
              ],
              actor: owner
            )
          )

        inv2 =
          generate(
            workspace_invitation(
              [
                workspace_id: workspace.id
              ],
              actor: owner
            )
          )

        # Tokens should be completely different (not sequential)
        refute inv1.token == inv2.token
        # They shouldn't share common prefixes (indicating sequential generation)
        refute String.starts_with?(inv2.token, String.slice(inv1.token, 0..10))
      end
    end
  end

  describe "invitation expiration properties" do
    property "newly created invitations are never expired" do
      check all(_ <- integer(1..25)) do
        owner = generate(user())
        workspace = generate(workspace([], actor: owner))

        invitation =
          generate(
            workspace_invitation(
              [
                workspace_id: workspace.id
              ],
              actor: owner
            )
          )

        # Load with is_expired calculation
        invitation_with_calc =
          Accounts.get_invitation_by_token!(
            invitation.token,
            load: [:is_expired]
          )

        refute invitation_with_calc.is_expired,
               "Newly created invitation should not be expired"

        # expires_at should be in the future
        assert DateTime.compare(invitation.expires_at, DateTime.utc_now()) == :gt
      end
    end

    property "invitations have consistent expiration period" do
      check all(_ <- integer(1..50)) do
        owner = generate(user())
        workspace = generate(workspace([], actor: owner))

        before = DateTime.utc_now()

        invitation =
          generate(
            workspace_invitation(
              [
                workspace_id: workspace.id
              ],
              actor: owner
            )
          )

        _after_create = DateTime.utc_now()

        # Expiration should be approximately 7 days from now
        # Allow some variance for test execution time
        expires_in_seconds = DateTime.diff(invitation.expires_at, before)
        seven_days_in_seconds = 7 * 24 * 60 * 60

        # Should be within 7 days +/- 10 seconds
        assert_in_delta expires_in_seconds,
                        seven_days_in_seconds,
                        10,
                        "Expiration not set to 7 days"
      end
    end
  end

  describe "invitation state transition properties" do
    property "unaccepted invitations have nil accepted_at" do
      check all(_ <- integer(1..25)) do
        owner = generate(user())
        workspace = generate(workspace([], actor: owner))

        invitation =
          generate(
            workspace_invitation(
              [
                workspace_id: workspace.id
              ],
              actor: owner
            )
          )

        # Load with is_accepted calculation
        invitation_with_calc =
          Accounts.get_invitation_by_token!(
            invitation.token,
            load: [:is_accepted]
          )

        assert is_nil(invitation.accepted_at)
        refute invitation_with_calc.is_accepted
      end
    end

    property "accepting invitation sets accepted_at timestamp" do
      check all(_ <- integer(1..50)) do
        owner = generate(user())
        invitee = generate(user())
        workspace = generate(workspace([], actor: owner))

        # Upgrade to pro to allow multiple members (accepting adds member)
        org =
          Citadel.Accounts.get_organization_by_id!(workspace.organization_id, authorize?: false)

        upgrade_to_pro(org)

        invitation =
          generate(
            workspace_invitation(
              [
                email: invitee.email,
                workspace_id: workspace.id
              ],
              actor: owner
            )
          )

        before_accept = DateTime.utc_now()

        # Accept invitation
        {:ok, accepted_invitation} =
          Accounts.accept_invitation(invitation, actor: invitee)

        after_accept = DateTime.utc_now()

        # accepted_at should be set
        refute is_nil(accepted_invitation.accepted_at)

        # accepted_at should be between before and after timestamps
        assert DateTime.compare(accepted_invitation.accepted_at, before_accept) in [:eq, :gt]
        assert DateTime.compare(accepted_invitation.accepted_at, after_accept) in [:eq, :lt]
      end
    end

    property "accepting invitation creates workspace membership" do
      check all(_ <- integer(1..50)) do
        owner = generate(user())
        invitee = generate(user())
        workspace = generate(workspace([], actor: owner))

        # Upgrade to pro to allow multiple members (accepting adds member)
        org =
          Citadel.Accounts.get_organization_by_id!(workspace.organization_id, authorize?: false)

        upgrade_to_pro(org)

        invitation =
          generate(
            workspace_invitation(
              [
                email: invitee.email,
                workspace_id: workspace.id
              ],
              actor: owner
            )
          )

        # Accept invitation
        {:ok, _accepted_invitation} =
          Accounts.accept_invitation(invitation, actor: invitee)

        # Verify membership was created
        memberships =
          Accounts.list_workspace_members!(
            actor: owner,
            query: [filter: [user_id: invitee.id, workspace_id: workspace.id]]
          )

        assert length(memberships) == 1
      end
    end
  end

  describe "invitation email validation properties" do
    property "invitations accept valid email formats" do
      check all(
              local <- string(:alphanumeric, min_length: 1, max_length: 20),
              domain <- string(:alphanumeric, min_length: 1, max_length: 20),
              tld <- member_of(["com", "org", "net", "edu"])
            ) do
        owner = generate(user())
        workspace = generate(workspace([], actor: owner))

        email = "#{local}@#{domain}.#{tld}"

        assert {:ok, invitation} =
                 Accounts.create_invitation(email, workspace.id, actor: owner)

        # Email is stored as CiString, compare case-insensitively
        assert String.downcase(to_string(invitation.email)) == String.downcase(email)
      end
    end

    property "invitations can be created for same email in different workspaces" do
      check all(_ <- integer(1..50)) do
        owner1 = generate(user())
        workspace1 = generate(workspace([], actor: owner1))
        owner2 = generate(user())
        workspace2 = generate(workspace([], actor: owner2))

        email = "user@example.com"

        # Should be able to invite same email to different workspaces
        {:ok, inv1} = Accounts.create_invitation(email, workspace1.id, actor: owner1)
        {:ok, inv2} = Accounts.create_invitation(email, workspace2.id, actor: owner2)

        assert inv1.email == inv2.email
        assert inv1.workspace_id != inv2.workspace_id
        # But tokens should be different
        refute inv1.token == inv2.token
      end
    end
  end
end
