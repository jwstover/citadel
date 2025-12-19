defmodule Citadel.Billing.CreditLedger.Types.TransactionType do
  @moduledoc """
  Types of credit transactions.

  - :purchase - Credits purchased via Stripe
  - :usage - Credits consumed by AI features
  - :refund - Credits refunded
  - :adjustment - Manual admin adjustment
  - :bonus - Promotional or reward credits
  """
  use Ash.Type.Enum, values: [:purchase, :usage, :refund, :adjustment, :bonus]
end
