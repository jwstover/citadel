defmodule Citadel.Billing.Subscription.Types.Status do
  @moduledoc """
  Subscription status values matching Stripe's subscription statuses.

  - :active - Subscription is active and paid
  - :canceled - Subscription has been canceled
  - :past_due - Payment failed, subscription still active
  - :trialing - In trial period
  """
  use Ash.Type.Enum, values: [:active, :canceled, :past_due, :trialing]
end
