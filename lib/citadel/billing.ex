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
      define :change_tier, action: :change_tier, args: [:new_tier]
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

      define :reserve_credits,
        action: :reserve_credits,
        args: [:organization_id, :amount, :description]

      define :adjust_reservation,
        action: :adjust_reservation,
        args: [:organization_id, :reserved_amount, :actual_cost, :description]
    end

    resource Citadel.Billing.ProcessedWebhookEvent do
      define :record_webhook_event, action: :record, args: [:stripe_event_id, :event_type]
      define :event_processed?, action: :event_processed?, args: [:stripe_event_id]
      define :cleanup_old_webhook_events, action: :cleanup_old_events
    end
  end
end
