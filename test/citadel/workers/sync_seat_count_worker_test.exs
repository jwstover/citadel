defmodule Citadel.Workers.SyncSeatCountWorkerTest do
  use Citadel.DataCase, async: true

  alias Citadel.Billing
  alias Citadel.Workers.SyncSeatCountWorker

  setup do
    owner = generate(user())
    organization = generate(organization([], actor: owner))

    {:ok, owner: owner, organization: organization}
  end

  describe "perform/1" do
    test "succeeds when organization has no subscription", %{organization: organization} do
      # Delete any auto-created subscription
      case Billing.get_subscription_by_organization(organization.id, authorize?: false) do
        {:ok, sub} -> Ash.destroy!(sub, authorize?: false)
        _ -> :ok
      end

      # Should succeed silently
      assert :ok =
               SyncSeatCountWorker.perform(%Oban.Job{
                 args: %{"organization_id" => organization.id}
               })
    end

    test "succeeds when subscription has no Stripe subscription ID", %{
      organization: organization
    } do
      # Get the subscription (without stripe_subscription_id)
      subscription = Billing.get_subscription_by_organization!(organization.id, authorize?: false)
      assert subscription.stripe_subscription_id == nil

      # Should succeed silently
      assert :ok =
               SyncSeatCountWorker.perform(%Oban.Job{
                 args: %{"organization_id" => organization.id}
               })
    end

    test "counts members correctly", %{organization: organization} do
      require Ash.Query

      # The organization starts with 1 member (the owner)
      # Add another member
      other_user = generate(user())

      Citadel.Accounts.add_organization_member!(
        organization.id,
        other_user.id,
        :member,
        authorize?: false
      )

      # Count should be 2
      count =
        Citadel.Accounts.OrganizationMembership
        |> Ash.Query.filter(organization_id == ^organization.id)
        |> Ash.count!(authorize?: false)

      assert count == 2
    end
  end

  describe "job uniqueness" do
    test "deduplicates jobs for same organization", %{organization: organization} do
      # Insert two jobs for the same org
      {:ok, job1} =
        %{organization_id: organization.id}
        |> SyncSeatCountWorker.new()
        |> Oban.insert()

      {:ok, job2} =
        %{organization_id: organization.id}
        |> SyncSeatCountWorker.new()
        |> Oban.insert()

      # Should be the same job (deduplicated)
      assert job1.id == job2.id
    end

    test "creates separate jobs for different organizations", %{owner: owner} do
      org1 = generate(organization([], actor: owner))
      org2 = generate(organization([], actor: owner))

      {:ok, job1} =
        %{organization_id: org1.id}
        |> SyncSeatCountWorker.new()
        |> Oban.insert()

      {:ok, job2} =
        %{organization_id: org2.id}
        |> SyncSeatCountWorker.new()
        |> Oban.insert()

      # Should be different jobs
      assert job1.id != job2.id
    end
  end

  describe "membership change triggers seat sync" do
    test "adding a member enqueues a sync job", %{organization: organization} do
      # Clear any pending jobs
      Oban.drain_queue(queue: :billing)

      # Add a member
      other_user = generate(user())

      Citadel.Accounts.add_organization_member!(
        organization.id,
        other_user.id,
        :member,
        authorize?: false
      )

      # Check that a job was enqueued
      assert [job] = all_enqueued(queue: :billing)
      assert job.args["organization_id"] == organization.id
    end

    test "removing a member enqueues a sync job", %{organization: organization, owner: owner} do
      # Add a member first
      other_user = generate(user())

      membership =
        Citadel.Accounts.add_organization_member!(
          organization.id,
          other_user.id,
          :member,
          authorize?: false
        )

      # Clear any pending jobs
      Oban.drain_queue(queue: :billing)

      # Remove the member
      Citadel.Accounts.remove_organization_member!(membership, actor: owner)

      # Check that a job was enqueued
      assert [job] = all_enqueued(queue: :billing)
      assert job.args["organization_id"] == organization.id
    end
  end
end
