defmodule Citadel.Billing.Subscription do
  @moduledoc """
  Represents an organization's subscription to Citadel.
  Each organization has exactly one subscription (1:1 relationship).
  """
  use Ash.Resource,
    otp_app: :citadel,
    domain: Citadel.Billing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "subscriptions"
    repo Citadel.Repo

    references do
      reference :organization, on_delete: :delete, index?: true
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :organization_id,
        :tier,
        :billing_period,
        :seat_count,
        :current_period_start,
        :current_period_end
      ]

      change Citadel.Billing.Subscription.Changes.SetDefaultsForTier
      change set_attribute(:status, :active)
    end

    update :update do
      accept [
        :stripe_subscription_id,
        :stripe_customer_id,
        :status,
        :current_period_start,
        :current_period_end,
        :seat_count
      ]
    end

    update :upgrade_to_pro do
      accept [:billing_period, :stripe_subscription_id, :stripe_customer_id]

      change set_attribute(:tier, :pro)
      change set_attribute(:status, :active)
    end

    update :cancel do
      change set_attribute(:status, :canceled)
    end
  end

  policies do
    bypass action(:create) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if relates_to_actor_via([:organization, :owner])
      authorize_if expr(exists(organization.memberships, user_id == ^actor(:id)))
    end

    policy action_type(:update) do
      authorize_if relates_to_actor_via([:organization, :owner])

      authorize_if expr(
                     exists(
                       organization.memberships,
                       user_id == ^actor(:id) and role in [:owner, :admin]
                     )
                   )
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :tier, Citadel.Billing.Subscription.Types.Tier do
      allow_nil? false
      default :free
      public? true
    end

    attribute :billing_period, Citadel.Billing.Subscription.Types.BillingPeriod do
      allow_nil? true
      public? true
    end

    attribute :stripe_subscription_id, :string do
      allow_nil? true
      public? true
    end

    attribute :stripe_customer_id, :string do
      allow_nil? true
      public? true
    end

    attribute :status, Citadel.Billing.Subscription.Types.Status do
      allow_nil? false
      default :active
      public? true
    end

    attribute :current_period_start, :utc_datetime do
      allow_nil? true
      public? true
    end

    attribute :current_period_end, :utc_datetime do
      allow_nil? true
      public? true
    end

    attribute :seat_count, :integer do
      allow_nil? false
      default 1
      public? true
      constraints min: 1
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

  identities do
    identity :unique_organization, [:organization_id]
  end
end
