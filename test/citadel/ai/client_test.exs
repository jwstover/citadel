defmodule Citadel.AI.ClientTest do
  use Citadel.DataCase, async: true

  import Mox

  alias Citadel.AI.Client
  alias Citadel.AI.MockProvider

  setup :verify_on_exit!

  describe "send_message/3" do
    test "sends message to provider and returns response" do
      user = create_user()

      MockProvider
      |> expect(:default_model, fn -> "test-model" end)
      |> expect(:validate_config, fn %{api_key: _, model: _} -> :ok end)
      |> expect(:send_message, fn "Hello", ^user, %{api_key: _, model: _} ->
        {:ok, "Hi there!"}
      end)

      assert {:ok, "Hi there!"} =
               Client.send_message("Hello", user, provider: :anthropic, api_key: "test-key")
    end

    test "returns error when provider returns error" do
      user = create_user()

      MockProvider
      |> expect(:default_model, fn -> "test-model" end)
      |> expect(:validate_config, fn _ -> :ok end)
      |> expect(:send_message, fn _, _, _ ->
        {:error, :authentication_error, "Invalid API key"}
      end)

      assert {:error, :authentication_error, "Invalid API key"} =
               Client.send_message("Hello", user, provider: :anthropic, api_key: "bad-key")
    end

    test "returns error when API key not configured" do
      user = create_user()

      # Temporarily clear the anthropic API key for this test
      original_config = Application.get_env(:citadel, Citadel.AI)

      Application.put_env(
        :citadel,
        Citadel.AI,
        Keyword.put(original_config, :anthropic_api_key, nil)
      )

      try do
        assert {:error, :provider_not_configured, message} =
                 Client.send_message("Hello", user, provider: :anthropic)

        assert message =~ "API key not configured"
      after
        Application.put_env(:citadel, Citadel.AI, original_config)
      end
    end
  end

  describe "send_message!/3" do
    test "returns response on success" do
      user = create_user()

      MockProvider
      |> expect(:default_model, fn -> "test-model" end)
      |> expect(:validate_config, fn _ -> :ok end)
      |> expect(:send_message, fn _, _, _ -> {:ok, "Response"} end)

      assert "Response" =
               Client.send_message!("Hello", user, provider: :anthropic, api_key: "test-key")
    end

    test "raises on error" do
      user = create_user()

      MockProvider
      |> expect(:default_model, fn -> "test-model" end)
      |> expect(:validate_config, fn _ -> :ok end)
      |> expect(:send_message, fn _, _, _ ->
        {:error, :api_error, "Something went wrong"}
      end)

      assert_raise RuntimeError, "Something went wrong", fn ->
        Client.send_message!("Hello", user, provider: :anthropic, api_key: "test-key")
      end
    end
  end

  describe "stream_message/3" do
    test "calls callback for streaming chunks and returns complete message" do
      user = create_user()
      test_pid = self()

      MockProvider
      |> expect(:default_model, fn -> "test-model" end)
      |> expect(:validate_config, fn _ -> :ok end)
      |> expect(:stream_message, fn "Hello", ^user, %{api_key: _, model: _}, callback ->
        callback.("Hi ")
        callback.("there!")
        {:ok, "Hi there!"}
      end)

      callback = fn chunk ->
        send(test_pid, {:chunk, chunk})
        :ok
      end

      assert {:ok, "Hi there!"} =
               Client.stream_message(
                 "Hello",
                 user,
                 [provider: :anthropic, api_key: "test-key"],
                 callback
               )

      assert_receive {:chunk, "Hi "}
      assert_receive {:chunk, "there!"}
    end

    test "returns error when provider returns error" do
      user = create_user()

      MockProvider
      |> expect(:default_model, fn -> "test-model" end)
      |> expect(:validate_config, fn _ -> :ok end)
      |> expect(:stream_message, fn _, _, _, _ ->
        {:error, :rate_limit_error, "Rate limit exceeded"}
      end)

      callback = fn _chunk -> :ok end

      assert {:error, :rate_limit_error, "Rate limit exceeded"} =
               Client.stream_message(
                 "Hello",
                 user,
                 [provider: :anthropic, api_key: "test-key"],
                 callback
               )
    end
  end

  describe "stream_message!/3" do
    test "returns complete message on success" do
      user = create_user()

      MockProvider
      |> expect(:default_model, fn -> "test-model" end)
      |> expect(:validate_config, fn _ -> :ok end)
      |> expect(:stream_message, fn _, _, _, callback ->
        callback.("Response")
        {:ok, "Response"}
      end)

      callback = fn _chunk -> :ok end

      assert "Response" =
               Client.stream_message!(
                 "Hello",
                 user,
                 [provider: :anthropic, api_key: "test-key"],
                 callback
               )
    end

    test "raises on error" do
      user = create_user()

      MockProvider
      |> expect(:default_model, fn -> "test-model" end)
      |> expect(:validate_config, fn _ -> :ok end)
      |> expect(:stream_message, fn _, _, _, _ ->
        {:error, :authentication_error, "Invalid key"}
      end)

      callback = fn _chunk -> :ok end

      assert_raise RuntimeError, "Invalid key", fn ->
        Client.stream_message!(
          "Hello",
          user,
          [provider: :anthropic, api_key: "test-key"],
          callback
        )
      end
    end
  end

  describe "provider_available?/1" do
    test "returns true when API key is configured" do
      # Test environment has API keys configured
      assert Client.provider_available?(:anthropic)
      assert Client.provider_available?(:openai)
    end

    test "returns false when API key not configured" do
      # Temporarily clear the anthropic API key for this test
      original_config = Application.get_env(:citadel, Citadel.AI)

      Application.put_env(
        :citadel,
        Citadel.AI,
        original_config
        |> Keyword.put(:anthropic_api_key, nil)
        |> Keyword.put(:openai_api_key, nil)
      )

      try do
        refute Client.provider_available?(:anthropic)
        refute Client.provider_available?(:openai)
      after
        Application.put_env(:citadel, Citadel.AI, original_config)
      end
    end
  end

  describe "available_providers/0" do
    test "returns configured providers" do
      # Test environment has API keys configured
      assert :anthropic in Client.available_providers()
      assert :openai in Client.available_providers()
    end

    test "returns empty list when no providers configured" do
      original_config = Application.get_env(:citadel, Citadel.AI)

      Application.put_env(
        :citadel,
        Citadel.AI,
        original_config
        |> Keyword.put(:anthropic_api_key, nil)
        |> Keyword.put(:openai_api_key, nil)
      )

      try do
        assert Client.available_providers() == []
      after
        Application.put_env(:citadel, Citadel.AI, original_config)
      end
    end
  end

  describe "default_model/1" do
    test "returns correct default model for anthropic" do
      MockProvider
      |> expect(:default_model, fn -> "claude-3-5-sonnet-20241022" end)

      assert Client.default_model(:anthropic) == "claude-3-5-sonnet-20241022"
    end

    test "returns correct default model for openai" do
      MockProvider
      |> expect(:default_model, fn -> "gpt-4o" end)

      assert Client.default_model(:openai) == "gpt-4o"
    end
  end

  describe "create_chain/2" do
    test "creates chain with provider" do
      user = create_user()
      mock_chain = %LangChain.Chains.LLMChain{llm: nil}

      MockProvider
      |> expect(:default_model, fn -> "test-model" end)
      |> expect(:validate_config, fn _ -> :ok end)
      |> expect(:create_chain, fn ^user, %{api_key: _, model: _}, _opts ->
        {:ok, mock_chain}
      end)

      assert {:ok, ^mock_chain} =
               Client.create_chain(user, provider: :anthropic, api_key: "test-key")
    end

    test "returns error when provider returns error" do
      user = create_user()

      MockProvider
      |> expect(:default_model, fn -> "test-model" end)
      |> expect(:validate_config, fn _ -> :ok end)
      |> expect(:create_chain, fn _, _, _ ->
        {:error, :api_error, "Failed to create chain"}
      end)

      assert {:error, :api_error, "Failed to create chain"} =
               Client.create_chain(user, provider: :anthropic, api_key: "test-key")
    end
  end

  describe "create_chain!/2" do
    test "returns chain on success" do
      user = create_user()
      mock_chain = %LangChain.Chains.LLMChain{llm: nil}

      MockProvider
      |> expect(:default_model, fn -> "test-model" end)
      |> expect(:validate_config, fn _ -> :ok end)
      |> expect(:create_chain, fn _, _, _ -> {:ok, mock_chain} end)

      assert ^mock_chain =
               Client.create_chain!(user, provider: :anthropic, api_key: "test-key")
    end

    test "raises on error" do
      user = create_user()

      MockProvider
      |> expect(:default_model, fn -> "test-model" end)
      |> expect(:validate_config, fn _ -> :ok end)
      |> expect(:create_chain, fn _, _, _ ->
        {:error, :api_error, "Chain creation failed"}
      end)

      assert_raise RuntimeError, "Chain creation failed", fn ->
        Client.create_chain!(user, provider: :anthropic, api_key: "test-key")
      end
    end
  end
end
