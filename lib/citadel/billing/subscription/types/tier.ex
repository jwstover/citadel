defmodule Citadel.Billing.Subscription.Types.Tier do
  @moduledoc """
  Subscription tiers: :free or :pro
  """
  use Ash.Type.Enum, values: [:free, :pro]
end
