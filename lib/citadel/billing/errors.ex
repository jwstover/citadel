defmodule Citadel.Billing.Errors do
  @moduledoc """
  Billing-specific error definitions.

  These errors are raised when billing limits are exceeded or billing
  features are not available for the current subscription tier.
  """

  defmodule WorkspaceLimitExceeded do
    @moduledoc """
    Raised when attempting to create a workspace that would exceed
    the organization's subscription limit.
    """
    use Splode.Error, fields: [:limit, :current], class: :forbidden

    def message(%{limit: limit, current: current}) do
      "Workspace limit reached. Your plan allows #{limit} workspace(s), and you currently have #{current}. Please upgrade to add more."
    end
  end

  defmodule MemberLimitExceeded do
    @moduledoc """
    Raised when attempting to add a member that would exceed
    the organization's subscription limit.
    """
    use Splode.Error, fields: [:limit, :current], class: :forbidden

    def message(%{limit: limit, current: current}) do
      "Member limit reached. Your plan allows #{limit} member(s), and you currently have #{current}. Please upgrade to add more."
    end
  end

  defmodule InsufficientCredits do
    @moduledoc """
    Raised when attempting an AI operation without sufficient credits.
    """
    use Splode.Error, fields: [:required, :available], class: :forbidden

    def message(%{required: required, available: available}) do
      "Insufficient credits. Required: #{required}, Available: #{available}. Please add credits or upgrade your plan."
    end
  end

  defmodule BYOKNotAllowed do
    @moduledoc """
    Raised when attempting to use BYOK (Bring Your Own Key) on a tier
    that doesn't support it.
    """
    use Splode.Error, fields: [], class: :forbidden

    def message(_) do
      "BYOK (Bring Your Own Key) is only available on Pro plans. Please upgrade to use your own API key."
    end
  end
end
