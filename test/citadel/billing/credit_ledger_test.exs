defmodule Citadel.Billing.CreditLedgerTest do
  use Citadel.DataCase, async: true

  alias Citadel.Billing

  setup do
    owner = generate(user())
    organization = generate(organization([], actor: owner))

    {:ok, owner: owner, organization: organization}
  end

  describe "add_credits/4" do
    test "adds credits with positive amount", %{organization: organization} do
      entry =
        Billing.add_credits!(
          organization.id,
          500,
          "Monthly allocation",
          authorize?: false
        )

      assert entry.organization_id == organization.id
      assert entry.amount == 500
      assert entry.running_balance == 500
      assert entry.description == "Monthly allocation"
      assert entry.transaction_type == :purchase
    end

    test "calculates running balance across multiple entries", %{organization: organization} do
      entry1 =
        Billing.add_credits!(organization.id, 500, "Initial credits", authorize?: false)

      assert entry1.running_balance == 500

      entry2 =
        Billing.add_credits!(organization.id, 200, "Bonus credits", authorize?: false)

      assert entry2.running_balance == 700

      entry3 =
        Billing.add_credits!(organization.id, 300, "More credits", authorize?: false)

      assert entry3.running_balance == 1000
    end

    test "supports different transaction types", %{organization: organization} do
      entry =
        Billing.add_credits!(
          organization.id,
          100,
          "Referral bonus",
          %{transaction_type: :bonus},
          authorize?: false
        )

      assert entry.transaction_type == :bonus
    end

    test "supports reference fields", %{organization: organization} do
      ref_id = Ash.UUID.generate()

      entry =
        Billing.add_credits!(
          organization.id,
          100,
          "Refund for message",
          %{reference_type: "message", reference_id: ref_id},
          authorize?: false
        )

      assert entry.reference_type == "message"
      assert entry.reference_id == ref_id
    end
  end

  describe "deduct_credits/4" do
    test "deducts credits with negative amount stored", %{organization: organization} do
      Billing.add_credits!(organization.id, 500, "Initial credits", authorize?: false)

      entry =
        Billing.deduct_credits!(
          organization.id,
          100,
          "AI usage",
          authorize?: false
        )

      assert entry.amount == -100
      assert entry.running_balance == 400
      assert entry.transaction_type == :usage
      assert entry.description == "AI usage"
    end

    test "fails when insufficient credits", %{organization: organization} do
      Billing.add_credits!(organization.id, 50, "Initial credits", authorize?: false)

      assert_raise Ash.Error.Invalid, ~r/insufficient credits/, fn ->
        Billing.deduct_credits!(organization.id, 100, "AI usage", authorize?: false)
      end
    end

    test "fails when no credits exist", %{organization: organization} do
      assert_raise Ash.Error.Invalid, ~r/insufficient credits/, fn ->
        Billing.deduct_credits!(organization.id, 10, "AI usage", authorize?: false)
      end
    end

    test "allows deduction equal to balance", %{organization: organization} do
      Billing.add_credits!(organization.id, 100, "Initial credits", authorize?: false)

      entry =
        Billing.deduct_credits!(organization.id, 100, "Full deduction", authorize?: false)

      assert entry.running_balance == 0
    end

    test "supports reference fields for usage tracking", %{organization: organization} do
      Billing.add_credits!(organization.id, 500, "Initial credits", authorize?: false)

      message_id = Ash.UUID.generate()

      entry =
        Billing.deduct_credits!(
          organization.id,
          50,
          "Claude message",
          %{reference_type: "message", reference_id: message_id},
          authorize?: false
        )

      assert entry.reference_type == "message"
      assert entry.reference_id == message_id
    end
  end

  describe "get_organization_balance/2" do
    test "returns 0 for organization with no entries", %{organization: organization} do
      assert {:ok, 0} = Billing.get_organization_balance(organization.id, authorize?: false)
    end

    test "returns current balance after credits added", %{organization: organization} do
      Billing.add_credits!(organization.id, 500, "Credits", authorize?: false)

      assert {:ok, 500} = Billing.get_organization_balance(organization.id, authorize?: false)
    end

    test "returns current balance after mixed transactions", %{organization: organization} do
      Billing.add_credits!(organization.id, 1000, "Initial", authorize?: false)
      Billing.deduct_credits!(organization.id, 300, "Usage 1", authorize?: false)
      Billing.add_credits!(organization.id, 200, "Bonus", authorize?: false)
      Billing.deduct_credits!(organization.id, 150, "Usage 2", authorize?: false)

      assert {:ok, 750} = Billing.get_organization_balance(organization.id, authorize?: false)
    end
  end

  describe "list_credit_entries/1" do
    test "lists all entries for organization", %{owner: owner, organization: organization} do
      Billing.add_credits!(organization.id, 500, "Entry 1", authorize?: false)
      Billing.add_credits!(organization.id, 200, "Entry 2", authorize?: false)
      Billing.deduct_credits!(organization.id, 100, "Entry 3", authorize?: false)

      entries = Billing.list_credit_entries!(actor: owner)

      assert length(entries) == 3

      descriptions = Enum.map(entries, & &1.description)
      assert "Entry 1" in descriptions
      assert "Entry 2" in descriptions
      assert "Entry 3" in descriptions
    end
  end

  describe "authorization" do
    test "organization owner can read credit entries", %{owner: owner, organization: organization} do
      Billing.add_credits!(organization.id, 500, "Credits", authorize?: false)

      entries = Billing.list_credit_entries!(actor: owner)
      assert length(entries) == 1
    end

    test "organization member can read credit entries", %{organization: organization} do
      Billing.add_credits!(organization.id, 500, "Credits", authorize?: false)

      member = generate(user())

      generate(
        organization_membership(
          [organization_id: organization.id, user_id: member.id, role: :member],
          authorize?: false
        )
      )

      entries = Billing.list_credit_entries!(actor: member)
      assert length(entries) == 1
    end

    test "non-member cannot read credit entries", %{organization: organization} do
      Billing.add_credits!(organization.id, 500, "Credits", authorize?: false)

      non_member = generate(user())

      entries = Billing.list_credit_entries!(actor: non_member)
      assert entries == []
    end
  end

  describe "concurrent balance updates" do
    test "maintains correct running balance with sequential updates", %{
      organization: organization
    } do
      for i <- 1..10 do
        Billing.add_credits!(
          organization.id,
          100,
          "Credit #{i}",
          authorize?: false
        )
      end

      assert {:ok, 1000} = Billing.get_organization_balance(organization.id, authorize?: false)

      for i <- 1..5 do
        Billing.deduct_credits!(
          organization.id,
          50,
          "Deduction #{i}",
          authorize?: false
        )
      end

      assert {:ok, 750} = Billing.get_organization_balance(organization.id, authorize?: false)
    end
  end
end
