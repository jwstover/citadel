defmodule Citadel.Settings.FeatureFlag do
  @moduledoc """
  Global feature flags for runtime control of application features.

  Feature flags are independent from subscription tier features and can use any atom
  as a key. They provide runtime control for:

  - **Operational controls**: Gradual rollouts, killswitches, maintenance mode
  - **Experiments**: A/B testing, beta features, user research
  - **Development**: Feature development, staging environments
  - **Overrides**: When a flag key matches a billing feature, it overrides tier access

  ## Two Independent Systems

  1. **Feature Flags** (this resource) - Runtime operational controls with any atom key
  2. **Subscription Tier Features** (Citadel.Billing.Features) - Product features tied to billing

  ## Override Behavior

  When checking feature access (e.g., `Plan.org_has_feature?/2`):
  1. Feature flags are checked first
  2. If flag key matches a billing feature → flag value overrides tier access
  3. If flag key doesn't match billing → flag value used directly
  4. If no flag exists → falls back to tier features (billing only)

  ## Examples

  ```elixir
  # Non-billing flag (operational control)
  Settings.create_feature_flag!(%{
    key: :beta_ui_redesign,
    enabled: true,
    description: "New dashboard UI for beta testers"
  })

  # Billing feature override (global enable/disable)
  Settings.create_feature_flag!(%{
    key: :api_access,  # Matches Citadel.Billing.Features
    enabled: true,
    description: "Enable API access for all orgs during testing"
  })
  ```

  ## Cache Strategy

  Feature flags are cached in ETS for performance. The cache is invalidated
  via PubSub notifications when flags are created, updated, or deleted.
  """
  use Ash.Resource,
    otp_app: :citadel,
    domain: Citadel.Settings,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    table "feature_flags"
    repo Citadel.Repo
  end

  actions do
    defaults [:read, :destroy]

    read :by_key do
      argument :key, :atom, allow_nil?: false
      filter expr(key == ^arg(:key))
      get? true
    end

    create :create do
      accept [:key, :enabled, :description]
    end

    update :update do
      primary? true
      require_atomic? false
      accept [:enabled, :description]
    end
  end

  policies do
    policy do
      authorize_if always()
    end
  end

  pub_sub do
    module CitadelWeb.Endpoint
    prefix "feature_flags"

    publish_all :create, "changed"
    publish_all :update, "changed"
    publish_all :destroy, "changed"
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :key, :atom do
      allow_nil? false
      public? true
      constraints [unsafe_to_atom?: true]

      description "Feature flag key (any atom). When key matches a billing feature, flag overrides tier access."
    end

    attribute :enabled, :boolean do
      allow_nil? false
      public? true
      default false
      description "Whether the feature is enabled globally"
    end

    attribute :description, :string do
      public? true
      description "Optional description or reason for the flag"
    end

    timestamps()
  end

  identities do
    identity :unique_key, [:key]
  end
end
