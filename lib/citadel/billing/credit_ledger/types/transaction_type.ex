defmodule Citadel.Billing.CreditLedger.Types.TransactionType do
  @moduledoc """
  Types of credit transactions.

  - :purchase - Credits purchased via Stripe
  - :usage - Credits consumed by AI features
  - :refund - Credits refunded
  - :adjustment - Manual admin adjustment
  - :bonus - Promotional or reward credits
  - :reservation - Credits reserved upfront before AI operation (used to prevent TOCTOU)
  - :reservation_adjustment - Adjustment to a previous reservation (refund or additional charge)
  """
  use Ash.Type.Enum,
    values: [:purchase, :usage, :refund, :adjustment, :bonus, :reservation, :reservation_adjustment]
end
