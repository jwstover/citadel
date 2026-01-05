defmodule Citadel.Workers.MonthlyCreditResetWorkerTest do
  use Citadel.DataCase, async: true

  alias Citadel.Billing
  alias Citadel.Billing.Plan
  alias Citadel.Workers.MonthlyCreditResetWorker

  setup do
    owner = generate(user())
    organization = generate(organization([], actor: owner))

    {:ok, owner: owner, organization: organization}
  end

  defp yesterday_datetime do
    DateTime.utc_now()
    |> DateTime.add(-1, :day)
    |> DateTime.truncate(:second)
  end

  defp future_datetime(days) do
    DateTime.utc_now()
    |> DateTime.add(days, :day)
    |> DateTime.truncate(:second)
  end

  describe "perform/1" do
    test "adds monthly credits for free tier subscription", %{organization: organization} do
      # Create a free subscription that needs reset
      _subscription =
        generate(
          subscription(
            [
              organization_id: organization.id,
              tier: :free,
              current_period_end: yesterday_datetime()
            ],
            authorize?: false
          )
        )

      assert :ok = perform_job(MonthlyCreditResetWorker, %{})

      # Check credits were added
      {:ok, balance} = Billing.get_organization_balance(organization.id, authorize?: false)
      assert balance == Plan.monthly_credits(:free)
      assert balance == 1000
    end

    test "adds monthly credits for pro tier subscription", %{organization: organization} do
      _subscription =
        generate(
          subscription(
            [
              organization_id: organization.id,
              tier: :pro,
              billing_period: :monthly,
              current_period_end: yesterday_datetime()
            ],
            authorize?: false
          )
        )

      assert :ok = perform_job(MonthlyCreditResetWorker, %{})

      {:ok, balance} = Billing.get_organization_balance(organization.id, authorize?: false)
      assert balance == Plan.monthly_credits(:pro)
      assert balance == 10_000
    end

    test "updates subscription period dates", %{organization: organization} do
      yesterday = yesterday_datetime()

      subscription =
        generate(
          subscription(
            [
              organization_id: organization.id,
              tier: :free,
              current_period_start: DateTime.add(yesterday, -30, :day),
              current_period_end: yesterday
            ],
            authorize?: false
          )
        )

      assert :ok = perform_job(MonthlyCreditResetWorker, %{})

      # Reload subscription
      updated_subscription = Billing.get_subscription!(subscription.id, authorize?: false)

      # Period start should be today (as DateTime)
      assert DateTime.to_date(updated_subscription.current_period_start) == Date.utc_today()
      assert updated_subscription.current_period_end != nil

      # Period end should be in the future
      assert DateTime.compare(updated_subscription.current_period_end, DateTime.utc_now()) == :gt
    end

    test "is idempotent - doesn't double reset", %{organization: organization} do
      _subscription =
        generate(
          subscription(
            [
              organization_id: organization.id,
              tier: :free,
              current_period_end: yesterday_datetime()
            ],
            authorize?: false
          )
        )

      # First run
      assert :ok = perform_job(MonthlyCreditResetWorker, %{})

      {:ok, balance_after_first} =
        Billing.get_organization_balance(organization.id, authorize?: false)

      assert balance_after_first == 1000

      # Second run (should not add more credits)
      assert :ok = perform_job(MonthlyCreditResetWorker, %{})

      {:ok, balance_after_second} =
        Billing.get_organization_balance(organization.id, authorize?: false)

      assert balance_after_second == 1000
    end

    test "skips subscriptions not yet due for reset", %{organization: organization} do
      # Subscription with future period end
      _subscription =
        generate(
          subscription(
            [
              organization_id: organization.id,
              tier: :free,
              current_period_end: future_datetime(15)
            ],
            authorize?: false
          )
        )

      assert :ok = perform_job(MonthlyCreditResetWorker, %{})

      # No credits should be added
      {:ok, balance} = Billing.get_organization_balance(organization.id, authorize?: false)
      assert balance == 0
    end

    test "handles subscriptions with nil period end", %{organization: organization} do
      # New subscription with no period set
      _subscription =
        generate(
          subscription(
            [
              organization_id: organization.id,
              tier: :free,
              current_period_end: nil
            ],
            authorize?: false
          )
        )

      assert :ok = perform_job(MonthlyCreditResetWorker, %{})

      # Should process subscriptions with nil period_end
      {:ok, balance} = Billing.get_organization_balance(organization.id, authorize?: false)
      assert balance == 1000
    end

    test "skips canceled subscriptions", %{organization: organization} do
      subscription =
        generate(
          subscription(
            [
              organization_id: organization.id,
              tier: :free,
              current_period_end: yesterday_datetime()
            ],
            authorize?: false
          )
        )

      # Cancel the subscription
      Billing.cancel_subscription!(subscription, authorize?: false)

      assert :ok = perform_job(MonthlyCreditResetWorker, %{})

      # No credits added for canceled subscription
      {:ok, balance} = Billing.get_organization_balance(organization.id, authorize?: false)
      assert balance == 0
    end

    test "processes multiple subscriptions" do
      # Create multiple organizations with subscriptions
      owner1 = generate(user())
      org1 = generate(organization([], actor: owner1))

      generate(
        subscription(
          [organization_id: org1.id, tier: :free, current_period_end: nil],
          authorize?: false
        )
      )

      owner2 = generate(user())
      org2 = generate(organization([], actor: owner2))

      generate(
        subscription(
          [
            organization_id: org2.id,
            tier: :pro,
            billing_period: :monthly,
            current_period_end: nil
          ],
          authorize?: false
        )
      )

      assert :ok = perform_job(MonthlyCreditResetWorker, %{})

      {:ok, balance1} = Billing.get_organization_balance(org1.id, authorize?: false)
      {:ok, balance2} = Billing.get_organization_balance(org2.id, authorize?: false)

      assert balance1 == 1000
      assert balance2 == 10_000
    end
  end
end
