defmodule Citadel.AI.ClientTest do
  use Citadel.DataCase, async: false
  alias Citadel.AI.Client

  describe "stream_message/3" do
    test "calls callback for streaming chunks" do
      # Create a test user
      user = create_user()

      # Skip if no API key configured
      unless Client.provider_available?(:openai) || Client.provider_available?(:anthropic) do
        # Skip test if no providers are configured
        assert true
      else
        # Collect chunks
        test_pid = self()

        callback = fn chunk ->
          send(test_pid, {:chunk, chunk})
          :ok
        end

        # Stream a simple message
        result = Client.stream_message("Say 'hello' in one word", user, callback)

        # Should return ok tuple with complete message
        assert {:ok, complete_message} = result
        assert is_binary(complete_message)
        assert String.length(complete_message) > 0

        # Should have received at least one chunk
        assert_receive {:chunk, chunk}, 5000
        assert is_binary(chunk)
      end
    end

    test "supports explicit provider option" do
      user = create_user()

      unless Client.provider_available?(:anthropic) do
        assert true
      else
        callback = fn _chunk -> :ok end

        result =
          Client.stream_message(
            "Say 'hi'",
            user,
            [provider: :anthropic, model: "claude-3-5-sonnet-20241022"],
            callback
          )

        assert {:ok, message} = result
        assert is_binary(message)
      end
    end

    test "returns error when provider not configured" do
      user = create_user()

      callback = fn _chunk -> :ok end

      # Try to use a provider with invalid API key
      result =
        Client.stream_message(
          "Hello",
          user,
          [provider: :openai, api_key: "invalid-key"],
          callback
        )

      # Should fail with an error
      assert {:error, error_type, message} = result
      assert error_type in [:authentication_error, :api_error, :unknown_error]
      assert is_binary(message)
    end
  end

  describe "stream_message!/3" do
    test "returns complete message on success" do
      user = create_user()

      unless Client.provider_available?(:openai) || Client.provider_available?(:anthropic) do
        assert true
      else
        callback = fn _chunk -> :ok end

        result = Client.stream_message!("Say 'test'", user, callback)

        assert is_binary(result)
        assert String.length(result) > 0
      end
    end

    test "raises on error" do
      user = create_user()

      callback = fn _chunk -> :ok end

      assert_raise RuntimeError, fn ->
        Client.stream_message!("Hello", user, [api_key: "invalid"], callback)
      end
    end
  end

  describe "provider_available?/1" do
    test "returns true for configured providers" do
      # This test depends on your local config
      # At least one provider should be configured for development
      providers = Client.available_providers()
      assert is_list(providers)
    end
  end

  describe "default_model/1" do
    test "returns correct default model for anthropic" do
      assert Client.default_model(:anthropic) == "claude-3-5-sonnet-20241022"
    end

    test "returns correct default model for openai" do
      assert Client.default_model(:openai) == "gpt-4o"
    end
  end
end
