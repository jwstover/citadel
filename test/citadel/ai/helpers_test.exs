defmodule Citadel.AI.HelpersTest do
  use ExUnit.Case, async: false

  import Mox

  alias Citadel.AI.Helpers
  alias Citadel.AI.MockProvider

  setup :set_mox_global
  setup :verify_on_exit!

  describe "get_model_if_available/2" do
    test "returns model when provider is configured" do
      MockProvider
      |> expect(:default_model, fn -> "test-model" end)

      model = Helpers.get_model_if_available(:anthropic)
      assert model != nil
    end

    test "returns nil when anthropic not configured" do
      original_config = Application.get_env(:citadel, Citadel.AI)

      Application.put_env(
        :citadel,
        Citadel.AI,
        Keyword.put(original_config, :anthropic_api_key, nil)
      )

      try do
        assert Helpers.get_model_if_available(:anthropic) == nil
      after
        Application.put_env(:citadel, Citadel.AI, original_config)
      end
    end

    test "returns nil when openai not configured" do
      original_config = Application.get_env(:citadel, Citadel.AI)

      Application.put_env(
        :citadel,
        Citadel.AI,
        Keyword.put(original_config, :openai_api_key, nil)
      )

      try do
        assert Helpers.get_model_if_available(:openai) == nil
      after
        Application.put_env(:citadel, Citadel.AI, original_config)
      end
    end

    test "returns nil when default provider not configured" do
      original_config = Application.get_env(:citadel, Citadel.AI)

      Application.put_env(
        :citadel,
        Citadel.AI,
        original_config
        |> Keyword.put(:anthropic_api_key, nil)
        |> Keyword.put(:openai_api_key, nil)
      )

      try do
        assert Helpers.get_model_if_available() == nil
      after
        Application.put_env(:citadel, Citadel.AI, original_config)
      end
    end
  end

  describe "get_model/2" do
    test "raises when API key not configured" do
      original_config = Application.get_env(:citadel, Citadel.AI)

      Application.put_env(
        :citadel,
        Citadel.AI,
        Keyword.put(original_config, :anthropic_api_key, nil)
      )

      try do
        assert_raise ArgumentError, ~r/API key not configured/, fn ->
          Helpers.get_model(:anthropic)
        end
      after
        Application.put_env(:citadel, Citadel.AI, original_config)
      end
    end

    test "returns Anthropic model when provider is anthropic" do
      MockProvider
      |> expect(:default_model, fn -> "claude-3-5-sonnet-20241022" end)

      model = Helpers.get_model(:anthropic, api_key: "test-key")
      assert model.__struct__ == LangChain.ChatModels.ChatAnthropic
    end

    test "returns OpenAI model when provider is openai" do
      MockProvider
      |> expect(:default_model, fn -> "gpt-4o" end)

      model = Helpers.get_model(:openai, api_key: "test-key")
      assert model.__struct__ == LangChain.ChatModels.ChatOpenAI
    end

    test "raises for unsupported provider" do
      assert_raise ArgumentError, ~r/Unsupported provider/, fn ->
        Helpers.get_model(:unknown, api_key: "test-key")
      end
    end
  end
end
