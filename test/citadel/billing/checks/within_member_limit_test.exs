defmodule Citadel.Billing.Checks.WithinMemberLimitTest do
  use Citadel.DataCase, async: true

  import Citadel.Generator

  describe "member limit enforcement" do
    test "free tier allows only 1 member (the owner)" do
      owner = generate(user())
      org = generate(organization([], actor: owner))

      # Owner is already a member from org creation, try adding another
      new_user = generate(user())

      assert {:error, %Ash.Error.Forbidden{}} =
               Citadel.Accounts.add_organization_member(
                 org.id,
                 new_user.id,
                 :member,
                 actor: owner
               )
    end

    test "pro tier allows up to 5 members" do
      owner = generate(user())
      org = generate(organization([], actor: owner))

      # Upgrade to pro
      generate(
        subscription([organization_id: org.id, tier: :pro, billing_period: :monthly],
          authorize?: false
        )
      )

      # Add 4 more members (owner + 4 = 5 total)
      for _ <- 1..4 do
        new_user = generate(user())

        Citadel.Accounts.add_organization_member!(
          org.id,
          new_user.id,
          :member,
          actor: owner
        )
      end

      # 6th member should fail
      sixth_user = generate(user())

      assert {:error, %Ash.Error.Forbidden{}} =
               Citadel.Accounts.add_organization_member(
                 org.id,
                 sixth_user.id,
                 :member,
                 actor: owner
               )
    end
  end
end
