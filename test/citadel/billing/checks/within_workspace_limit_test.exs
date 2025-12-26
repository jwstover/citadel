defmodule Citadel.Billing.Checks.WithinWorkspaceLimitTest do
  use Citadel.DataCase, async: true

  import Citadel.Generator

  describe "workspace limit enforcement" do
    test "allows creating workspace when under limit (free tier)" do
      owner = generate(user())
      org = generate(organization([], actor: owner))

      # Free tier allows 1 workspace - this should succeed
      workspace =
        generate(workspace([organization_id: org.id], actor: owner))

      assert workspace.organization_id == org.id
    end

    test "denies creating workspace when at limit (free tier)" do
      owner = generate(user())
      org = generate(organization([], actor: owner))

      # Create first workspace (uses the limit)
      generate(workspace([organization_id: org.id], actor: owner))

      # Second workspace should fail
      assert {:error, %Ash.Error.Forbidden{}} =
               Citadel.Accounts.create_workspace(
                 "Second Workspace",
                 %{organization_id: org.id},
                 actor: owner
               )
    end

    test "allows creating up to 5 workspaces for pro tier" do
      owner = generate(user())
      org = generate(organization([], actor: owner))

      # Upgrade to pro
      generate(
        subscription([organization_id: org.id, tier: :pro, billing_period: :monthly],
          authorize?: false
        )
      )

      # Create 5 workspaces - all should succeed
      for i <- 1..5 do
        generate(workspace([name: "Workspace #{i}", organization_id: org.id], actor: owner))
      end

      # 6th should fail
      assert {:error, %Ash.Error.Forbidden{}} =
               Citadel.Accounts.create_workspace(
                 "Workspace 6",
                 %{organization_id: org.id},
                 actor: owner
               )
    end

    test "allows creating workspace without organization (legacy)" do
      owner = generate(user())

      # Workspace without organization should still work
      workspace = generate(workspace([], actor: owner))

      assert workspace.organization_id == nil
    end
  end
end
