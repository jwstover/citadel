defmodule Citadel.Billing.Credits do
  @moduledoc """
  Credit calculation and configuration for AI usage.

  Converts token usage from LangChain responses into credit costs.
  Credits are a simplified unit that abstracts away the complexity
  of different model pricing.

  ## Configuration

  Configure credit costs in your application config:

      config :citadel, Citadel.Billing.Credits,
        default_cost_per_input_token: 0.003,
        default_cost_per_output_token: 0.015,
        models: %{
          "claude-sonnet-4-20250514" => %{input: 0.003, output: 0.015}
        },
        minimum_credits_required: 1

  ## Credit Calculation

  Credits are calculated as:
      credits = ceil(input_tokens * input_rate + output_tokens * output_rate)

  The result is always at least 1 credit (minimum charge).
  """

  alias Citadel.Billing

  @default_config %{
    default_cost_per_input_token: 0.003,
    default_cost_per_output_token: 0.015,
    models: %{},
    minimum_credits_required: 1,
    max_reservation_credits: 100
  }

  @doc """
  Calculates credits to deduct based on token usage.

  ## Options

    * `:model` - The model name to use for cost lookup (optional)

  ## Examples

      iex> usage = %LangChain.TokenUsage{input: 1000, output: 500}
      iex> Credits.calculate_cost(usage)
      11  # (1000 * 0.003) + (500 * 0.015) = 10.5, ceil = 11

      iex> Credits.calculate_cost(usage, model: "claude-sonnet-4-20250514")
      11

  """
  @spec calculate_cost(LangChain.TokenUsage.t() | nil, keyword()) :: non_neg_integer()
  def calculate_cost(token_usage, opts \\ [])

  def calculate_cost(nil, _opts), do: 1

  def calculate_cost(%LangChain.TokenUsage{input: input, output: output}, opts) do
    model = Keyword.get(opts, :model)
    config = model_config(model)

    raw_cost = (input || 0) * config.input + (output || 0) * config.output
    max(ceil(raw_cost), minimum_credits_required())
  end

  @doc """
  Gets the credit cost configuration for a specific model.

  Returns a map with `:input` and `:output` rates. Falls back to
  default rates if the model is not specifically configured.

  ## Examples

      iex> Credits.model_config("claude-sonnet-4-20250514")
      %{input: 0.003, output: 0.015}

      iex> Credits.model_config("unknown-model")
      %{input: 0.003, output: 0.015}

  """
  @spec model_config(String.t() | nil) :: %{input: float(), output: float()}
  def model_config(nil), do: default_rates()

  def model_config(model_name) do
    models = get_config(:models, %{})

    case Map.get(models, model_name) do
      nil -> default_rates()
      config -> config
    end
  end

  @doc """
  Checks if an organization has sufficient credits for a minimum operation.

  Returns `{:ok, balance}` if sufficient credits exist, or
  `{:error, :insufficient_credits, current_balance}` if not.

  ## Examples

      iex> Credits.check_sufficient_credits(org_id)
      {:ok, 500}

      iex> Credits.check_sufficient_credits(org_id, 1000)
      {:error, :insufficient_credits, 500}

  """
  @spec check_sufficient_credits(String.t(), non_neg_integer()) ::
          {:ok, non_neg_integer()} | {:error, :insufficient_credits, non_neg_integer()}
  def check_sufficient_credits(organization_id, minimum \\ nil) do
    minimum = minimum || minimum_credits_required()
    balance = Billing.get_organization_balance!(organization_id, authorize?: false)

    if balance >= minimum do
      {:ok, balance}
    else
      {:error, :insufficient_credits, balance}
    end
  end

  @doc """
  Returns the minimum credits required to start an AI request.
  """
  @spec minimum_credits_required() :: non_neg_integer()
  def minimum_credits_required do
    get_config(:minimum_credits_required, 1)
  end

  @doc """
  Returns the maximum credits to reserve upfront for an AI request.

  This is used to prevent TOCTOU race conditions by reserving a pessimistic
  amount of credits before the AI call. The reservation is adjusted to
  actual cost after completion.
  """
  @spec max_reservation_credits() :: non_neg_integer()
  def max_reservation_credits do
    get_config(:max_reservation_credits, @default_config.max_reservation_credits)
  end

  defp default_rates do
    %{
      input:
        get_config(:default_cost_per_input_token, @default_config.default_cost_per_input_token),
      output:
        get_config(:default_cost_per_output_token, @default_config.default_cost_per_output_token)
    }
  end

  defp get_config(key, default) do
    config = Application.get_env(:citadel, __MODULE__, [])

    case config do
      list when is_list(list) -> Keyword.get(list, key, default)
      map when is_map(map) -> Map.get(map, key, default)
      _ -> default
    end
  end
end
