defmodule Citadel.Billing.CreditLedger do
  @moduledoc """
  Tracks credit transactions for organizations.
  Uses a ledger pattern with running balances for efficient balance queries.
  """
  use Ash.Resource,
    otp_app: :citadel,
    domain: Citadel.Billing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  require Ash.Query

  postgres do
    table "credit_ledger"
    repo Citadel.Repo

    references do
      reference :organization, on_delete: :delete, index?: true
    end

    custom_indexes do
      index [:organization_id, :inserted_at]
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :organization_id,
        :amount,
        :description,
        :transaction_type,
        :reference_type,
        :reference_id
      ]

      transaction? true

      change Citadel.Billing.CreditLedger.Changes.CalculateRunningBalance
    end

    action :current_balance, :integer do
      argument :organization_id, :uuid, allow_nil?: false

      run fn input, _context ->
        org_id = input.arguments.organization_id

        balance =
          __MODULE__
          |> Ash.Query.filter(organization_id == ^org_id)
          |> Ash.Query.sort(inserted_at: :desc)
          |> Ash.Query.limit(1)
          |> Ash.Query.select([:running_balance])
          |> Ash.read_one!(authorize?: false)
          |> case do
            nil -> 0
            entry -> entry.running_balance
          end

        {:ok, balance}
      end
    end

    create :add_credits do
      accept []

      argument :organization_id, :uuid, allow_nil?: false
      argument :amount, :integer, allow_nil?: false, constraints: [min: 1]
      argument :description, :string, allow_nil?: false

      argument :transaction_type, Citadel.Billing.CreditLedger.Types.TransactionType,
        default: :purchase

      argument :reference_type, :string
      argument :reference_id, :uuid

      transaction? true

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.force_change_attribute(
          :organization_id,
          Ash.Changeset.get_argument(changeset, :organization_id)
        )
        |> Ash.Changeset.force_change_attribute(
          :amount,
          Ash.Changeset.get_argument(changeset, :amount)
        )
        |> Ash.Changeset.force_change_attribute(
          :description,
          Ash.Changeset.get_argument(changeset, :description)
        )
        |> Ash.Changeset.force_change_attribute(
          :transaction_type,
          Ash.Changeset.get_argument(changeset, :transaction_type)
        )
        |> Ash.Changeset.force_change_attribute(
          :reference_type,
          Ash.Changeset.get_argument(changeset, :reference_type)
        )
        |> Ash.Changeset.force_change_attribute(
          :reference_id,
          Ash.Changeset.get_argument(changeset, :reference_id)
        )
      end

      change Citadel.Billing.CreditLedger.Changes.CalculateRunningBalance
    end

    create :deduct_credits do
      accept []

      argument :organization_id, :uuid, allow_nil?: false
      argument :amount, :integer, allow_nil?: false, constraints: [min: 1]
      argument :description, :string, allow_nil?: false
      argument :reference_type, :string
      argument :reference_id, :uuid

      transaction? true

      change fn changeset, _context ->
        amount = Ash.Changeset.get_argument(changeset, :amount)

        changeset
        |> Ash.Changeset.force_change_attribute(
          :organization_id,
          Ash.Changeset.get_argument(changeset, :organization_id)
        )
        |> Ash.Changeset.force_change_attribute(:amount, -abs(amount))
        |> Ash.Changeset.force_change_attribute(
          :description,
          Ash.Changeset.get_argument(changeset, :description)
        )
        |> Ash.Changeset.force_change_attribute(:transaction_type, :usage)
        |> Ash.Changeset.force_change_attribute(
          :reference_type,
          Ash.Changeset.get_argument(changeset, :reference_type)
        )
        |> Ash.Changeset.force_change_attribute(
          :reference_id,
          Ash.Changeset.get_argument(changeset, :reference_id)
        )
      end

      change {Citadel.Billing.CreditLedger.Changes.CalculateRunningBalance, validate_balance?: true}
    end

    create :reserve_credits do
      @doc """
      Reserves credits upfront before an AI operation.

      This prevents TOCTOU race conditions by deducting credits atomically
      before the operation begins. The reservation can later be adjusted
      to the actual cost using adjust_reservation.
      """
      accept []

      argument :organization_id, :uuid, allow_nil?: false
      argument :amount, :integer, allow_nil?: false, constraints: [min: 1]
      argument :description, :string, allow_nil?: false
      argument :reference_type, :string
      argument :reference_id, :uuid

      transaction? true

      change fn changeset, _context ->
        amount = Ash.Changeset.get_argument(changeset, :amount)

        changeset
        |> Ash.Changeset.force_change_attribute(
          :organization_id,
          Ash.Changeset.get_argument(changeset, :organization_id)
        )
        |> Ash.Changeset.force_change_attribute(:amount, -abs(amount))
        |> Ash.Changeset.force_change_attribute(
          :description,
          Ash.Changeset.get_argument(changeset, :description)
        )
        |> Ash.Changeset.force_change_attribute(:transaction_type, :reservation)
        |> Ash.Changeset.force_change_attribute(
          :reference_type,
          Ash.Changeset.get_argument(changeset, :reference_type)
        )
        |> Ash.Changeset.force_change_attribute(
          :reference_id,
          Ash.Changeset.get_argument(changeset, :reference_id)
        )
      end

      change {Citadel.Billing.CreditLedger.Changes.CalculateRunningBalance, validate_balance?: true}
    end

    create :adjust_reservation do
      @doc """
      Adjusts a previous reservation to the actual cost.

      If actual_cost < reserved_amount: credits are refunded (positive adjustment)
      If actual_cost > reserved_amount: additional credits are charged (negative adjustment)
      If actual_cost == 0: full refund (operation failed/cancelled)
      """
      accept []

      argument :organization_id, :uuid, allow_nil?: false
      argument :reserved_amount, :integer, allow_nil?: false, constraints: [min: 0]
      argument :actual_cost, :integer, allow_nil?: false, constraints: [min: 0]
      argument :description, :string, allow_nil?: false
      argument :reference_type, :string
      argument :reference_id, :uuid

      transaction? true

      change fn changeset, _context ->
        reserved = Ash.Changeset.get_argument(changeset, :reserved_amount)
        actual = Ash.Changeset.get_argument(changeset, :actual_cost)
        adjustment = reserved - actual

        if adjustment == 0 do
          Ash.Changeset.add_error(changeset,
            field: :actual_cost,
            message: "no adjustment needed"
          )
        else
          changeset
          |> Ash.Changeset.force_change_attribute(
            :organization_id,
            Ash.Changeset.get_argument(changeset, :organization_id)
          )
          |> Ash.Changeset.force_change_attribute(:amount, adjustment)
          |> Ash.Changeset.force_change_attribute(
            :description,
            Ash.Changeset.get_argument(changeset, :description)
          )
          |> Ash.Changeset.force_change_attribute(:transaction_type, :reservation_adjustment)
          |> Ash.Changeset.force_change_attribute(
            :reference_type,
            Ash.Changeset.get_argument(changeset, :reference_type)
          )
          |> Ash.Changeset.force_change_attribute(
            :reference_id,
            Ash.Changeset.get_argument(changeset, :reference_id)
          )
        end
      end

      change {Citadel.Billing.CreditLedger.Changes.CalculateRunningBalance, validate_balance?: true}
    end
  end

  policies do
    bypass action_type(:create) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if relates_to_actor_via([:organization, :owner])
      authorize_if expr(exists(organization.memberships, user_id == ^actor(:id)))
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :amount, :integer do
      allow_nil? false
      public? true
      description "Positive for credits, negative for debits"
    end

    attribute :running_balance, :integer do
      allow_nil? false
      public? true
      writable? false
    end

    attribute :description, :string do
      allow_nil? false
      public? true
      constraints max_length: 500
    end

    attribute :transaction_type, Citadel.Billing.CreditLedger.Types.TransactionType do
      allow_nil? false
      public? true
    end

    attribute :reference_type, :string do
      allow_nil? true
      public? true
      description "Type of referenced entity (e.g., 'message', 'task_generation')"
    end

    attribute :reference_id, :uuid do
      allow_nil? true
      public? true
      description "ID of referenced entity"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :organization, Citadel.Accounts.Organization do
      allow_nil? false
      attribute_writable? true
      public? true
    end
  end
end
