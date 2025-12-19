defmodule Citadel.Billing do
  @moduledoc """
  The Billing domain manages subscriptions and credit ledger for organizations.
  """
  use Ash.Domain, otp_app: :citadel, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Citadel.Billing.Subscription do
      define :create_subscription, action: :create, args: [:organization_id, :tier]
      define :get_subscription_by_organization, action: :read, get_by: [:organization_id]
      define :get_subscription, action: :read, get_by: [:id]
      define :update_subscription, action: :update
      define :upgrade_to_pro, action: :upgrade_to_pro
      define :cancel_subscription, action: :cancel
    end

    resource Citadel.Billing.CreditLedger do
      define :create_credit_entry, action: :create
      define :list_credit_entries, action: :read
      define :get_organization_balance, action: :current_balance, args: [:organization_id]
      define :add_credits, action: :add_credits, args: [:organization_id, :amount, :description]

      define :deduct_credits,
        action: :deduct_credits,
        args: [:organization_id, :amount, :description]
    end
  end
end
