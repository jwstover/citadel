defmodule Citadel.Billing.Subscription.Types.BillingPeriod do
  @moduledoc """
  Billing periods: :monthly or :annual
  """
  use Ash.Type.Enum, values: [:monthly, :annual]
end
