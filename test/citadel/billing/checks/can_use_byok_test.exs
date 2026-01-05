defmodule Citadel.Billing.Checks.CanUseBYOKTest do
  use Citadel.DataCase, async: true

  import Citadel.Generator

  alias Citadel.Billing.Checks.CanUseBYOK

  describe "BYOK access check" do
    test "returns false for free tier organization" do
      owner = generate(user())
      org = generate(organization([], actor: owner))

      # Free tier by default - cannot use BYOK
      context = build_context_with_org(org.id)

      refute CanUseBYOK.match?(owner, context, [])
    end

    test "returns true for pro tier organization" do
      owner = generate(user())
      org = generate(organization([], actor: owner))

      # Upgrade to pro
      generate(
        subscription([organization_id: org.id, tier: :pro, billing_period: :monthly],
          authorize?: false
        )
      )

      context = build_context_with_org(org.id)

      assert CanUseBYOK.match?(owner, context, [])
    end

    test "returns false when no organization is provided" do
      owner = generate(user())

      # No organization in context
      context = %{}

      refute CanUseBYOK.match?(owner, context, [])
    end

    test "returns false for nil actor" do
      owner = generate(user())
      org = generate(organization([], actor: owner))

      context = build_context_with_org(org.id)

      refute CanUseBYOK.match?(nil, context, [])
    end
  end

  defp build_context_with_org(organization_id) do
    changeset = %Ash.Changeset{
      action_type: :create,
      resource: Citadel.Billing.Subscription,
      attributes: %{organization_id: organization_id}
    }

    %{changeset: changeset}
  end
end
