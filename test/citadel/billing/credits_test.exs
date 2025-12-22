defmodule Citadel.Billing.CreditsTest do
  use Citadel.DataCase, async: true

  alias Citadel.Billing
  alias Citadel.Billing.Credits

  setup do
    owner = generate(user())
    organization = generate(organization([], actor: owner))

    {:ok, owner: owner, organization: organization}
  end

  describe "calculate_cost/2" do
    test "calculates credits from token usage" do
      token_usage = %LangChain.TokenUsage{input: 1000, output: 500}

      # With default config: (1000 * 0.003) + (500 * 0.015) = 3 + 7.5 = 10.5 -> ceil = 11
      cost = Credits.calculate_cost(token_usage)

      assert cost == 11
    end

    test "rounds up fractional credits" do
      # Small usage should still result in at least 1 credit
      token_usage = %LangChain.TokenUsage{input: 10, output: 5}

      # (10 * 0.003) + (5 * 0.015) = 0.03 + 0.075 = 0.105 -> ceil = 1
      cost = Credits.calculate_cost(token_usage)

      assert cost == 1
    end

    test "returns minimum credits for nil token usage" do
      assert Credits.calculate_cost(nil) == 1
    end

    test "handles nil input/output tokens" do
      token_usage = %LangChain.TokenUsage{input: nil, output: nil}

      cost = Credits.calculate_cost(token_usage)

      assert cost == 1
    end

    test "handles zero tokens" do
      token_usage = %LangChain.TokenUsage{input: 0, output: 0}

      cost = Credits.calculate_cost(token_usage)

      # Should be minimum (1)
      assert cost == 1
    end

    test "calculates cost for large token counts" do
      # Simulating a long conversation
      token_usage = %LangChain.TokenUsage{input: 10_000, output: 5_000}

      # (10000 * 0.003) + (5000 * 0.015) = 30 + 75 = 105
      cost = Credits.calculate_cost(token_usage)

      assert cost == 105
    end
  end

  describe "model_config/1" do
    test "returns default config for unknown model" do
      config = Credits.model_config("unknown-model")

      assert config.input == 0.003
      assert config.output == 0.015
    end

    test "returns default config for nil model" do
      config = Credits.model_config(nil)

      assert config.input == 0.003
      assert config.output == 0.015
    end

    test "returns configured rates for known model" do
      # claude-sonnet-4-20250514 is configured in config.exs
      config = Credits.model_config("claude-sonnet-4-20250514")

      assert config.input == 0.003
      assert config.output == 0.015
    end
  end

  describe "check_sufficient_credits/2" do
    test "returns ok when credits are sufficient", %{organization: organization} do
      Billing.add_credits!(organization.id, 500, "Initial credits", authorize?: false)

      assert {:ok, 500} = Credits.check_sufficient_credits(organization.id)
    end

    test "returns ok when credits exactly meet minimum", %{organization: organization} do
      Billing.add_credits!(organization.id, 1, "Minimal credits", authorize?: false)

      assert {:ok, 1} = Credits.check_sufficient_credits(organization.id)
    end

    test "returns error when credits are insufficient", %{organization: organization} do
      # No credits added, balance is 0

      assert {:error, :insufficient_credits, 0} =
               Credits.check_sufficient_credits(organization.id)
    end

    test "returns error when credits below custom minimum", %{organization: organization} do
      Billing.add_credits!(organization.id, 50, "Some credits", authorize?: false)

      assert {:error, :insufficient_credits, 50} =
               Credits.check_sufficient_credits(organization.id, 100)
    end

    test "returns ok when credits meet custom minimum", %{organization: organization} do
      Billing.add_credits!(organization.id, 100, "Credits", authorize?: false)

      assert {:ok, 100} = Credits.check_sufficient_credits(organization.id, 100)
    end
  end

  describe "minimum_credits_required/0" do
    test "returns configured minimum" do
      # Default is 1
      assert Credits.minimum_credits_required() == 1
    end
  end
end
