defmodule Citadel.AI.ConfigTest do
  use ExUnit.Case, async: false

  alias Citadel.AI.Config

  describe "get_api_key/2" do
    test "returns API key when configured" do
      # Test environment has API keys configured
      assert {:ok, "test-anthropic-key"} = Config.get_api_key(:anthropic)
      assert {:ok, "test-openai-key"} = Config.get_api_key(:openai)
    end

    test "returns error when anthropic API key not configured" do
      original_config = Application.get_env(:citadel, Citadel.AI)

      Application.put_env(
        :citadel,
        Citadel.AI,
        Keyword.put(original_config, :anthropic_api_key, nil)
      )

      try do
        assert {:error, message} = Config.get_api_key(:anthropic)
        assert message =~ "Anthropic API key not configured"
      after
        Application.put_env(:citadel, Citadel.AI, original_config)
      end
    end

    test "returns error when openai API key not configured" do
      original_config = Application.get_env(:citadel, Citadel.AI)

      Application.put_env(
        :citadel,
        Citadel.AI,
        Keyword.put(original_config, :openai_api_key, nil)
      )

      try do
        assert {:error, message} = Config.get_api_key(:openai)
        assert message =~ "OpenAI API key not configured"
      after
        Application.put_env(:citadel, Citadel.AI, original_config)
      end
    end

    test "returns error for unknown provider" do
      assert {:error, _} = Config.get_api_key(:unknown)
    end
  end

  describe "get_api_key!/2" do
    test "returns API key when configured" do
      assert Config.get_api_key!(:anthropic) == "test-anthropic-key"
    end

    test "raises when API key not configured" do
      original_config = Application.get_env(:citadel, Citadel.AI)

      Application.put_env(
        :citadel,
        Citadel.AI,
        Keyword.put(original_config, :anthropic_api_key, nil)
      )

      try do
        assert_raise ArgumentError, ~r/API key not configured/, fn ->
          Config.get_api_key!(:anthropic)
        end
      after
        Application.put_env(:citadel, Citadel.AI, original_config)
      end
    end
  end

  describe "default_provider/0" do
    test "returns a valid provider atom" do
      provider = Config.default_provider()
      assert provider in [:anthropic, :openai]
    end
  end

  describe "provider_module/1" do
    test "returns Anthropic module for :anthropic" do
      assert Config.provider_module(:anthropic) == Citadel.AI.MockProvider
    end

    test "returns OpenAI module for :openai" do
      assert Config.provider_module(:openai) == Citadel.AI.MockProvider
    end

    test "raises for unknown provider" do
      assert_raise ArgumentError, ~r/Unknown provider/, fn ->
        Config.provider_module(:unknown)
      end
    end
  end

  describe "supported_providers/0" do
    test "returns list of supported providers" do
      providers = Config.supported_providers()
      assert :anthropic in providers
      assert :openai in providers
    end
  end

  describe "supported_provider?/1" do
    test "returns true for anthropic" do
      assert Config.supported_provider?(:anthropic)
    end

    test "returns true for openai" do
      assert Config.supported_provider?(:openai)
    end

    test "returns false for unknown provider" do
      refute Config.supported_provider?(:unknown)
    end
  end

  describe "provider_name/1" do
    test "returns 'Anthropic' for :anthropic" do
      assert Config.provider_name(:anthropic) == "Anthropic"
    end

    test "returns 'OpenAI' for :openai" do
      assert Config.provider_name(:openai) == "OpenAI"
    end

    test "returns string representation for unknown provider" do
      assert Config.provider_name(:unknown) == "unknown"
    end
  end
end
