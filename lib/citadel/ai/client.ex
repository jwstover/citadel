defmodule Citadel.AI.Client do
  @moduledoc """
  Main client interface for AI interactions.

  This module provides a unified interface for sending messages to various
  AI providers (Anthropic, OpenAI, etc.) and handles provider selection,
  configuration, and error handling.

  ## Examples

      # Using default provider (from config)
      Citadel.AI.Client.send_message("What's the weather?", current_user)

      # Explicitly selecting a provider
      Citadel.AI.Client.send_message("Hello!", current_user, provider: :openai)

      # Using a custom model
      Citadel.AI.Client.send_message("Hello!", current_user,
        provider: :anthropic,
        model: "claude-3-opus-20240229"
      )
  """

  alias Citadel.AI.Config
  alias Citadel.AI.Provider

  @type actor :: struct() | nil
  @type opts :: keyword()

  @doc """
  Sends a message to an AI provider and returns the response.

  ## Parameters
    - message: The user message to send
    - actor: The current user/actor making the request (used for AshAi context)
    - opts: Optional keyword list with the following options:
      - `:provider` - The provider to use (`:anthropic` or `:openai`). Defaults to configured default.
      - `:model` - The model to use. Defaults to provider's default model.
      - `:api_key` - Custom API key (future: for user-provided keys). Defaults to application config.

  ## Returns
    - `{:ok, response}` - Success with AI response
    - `{:error, :provider_not_configured, message}` - Provider API key not configured
    - `{:error, error_type, message}` - Other errors (see Citadel.AI.Provider for error types)

  ## Examples

      iex> {:ok, _response} = Citadel.AI.Client.send_message("Hello!", current_user)

      iex> Citadel.AI.Client.send_message("Translate 'hello' to Spanish", actor, provider: :openai)
      {:ok, "Hola"}

      iex> Citadel.AI.Client.send_message("Write a poem", actor,
      ...>   provider: :anthropic,
      ...>   model: "claude-3-opus-20240229")
      {:ok, "Roses are red..."}
  """
  @spec send_message(String.t(), actor(), opts()) ::
          {:ok, String.t()}
          | {:error, Provider.error_type() | :provider_not_configured, String.t()}
  def send_message(message, actor, opts \\ []) do
    provider = Keyword.get(opts, :provider, Config.default_provider())

    with {:ok, api_key} <- get_api_key(provider, opts),
         {:ok, provider_config} <- build_provider_config(provider, api_key, opts),
         {:ok, provider_module} <- get_provider_module(provider) do
      provider_module.send_message(message, actor, provider_config)
    end
  end

  @doc """
  Sends a message to an AI provider, raises on error.

  Same as `send_message/3` but raises on error instead of returning error tuple.

  ## Examples

      response = Citadel.AI.Client.send_message!("Hello!", current_user)
  """
  @spec send_message!(String.t(), actor(), opts()) :: String.t()
  def send_message!(message, actor, opts \\ []) do
    case send_message(message, actor, opts) do
      {:ok, response} -> response
      {:error, _type, message} -> raise RuntimeError, message
    end
  end

  @doc """
  Streams a message to an AI provider, calling callback for each chunk.

  The callback receives text deltas as they arrive from the AI provider.
  After streaming completes, the function returns the complete final message.

  ## Parameters
    - message: The user message to send
    - actor: The current user/actor making the request (used for AshAi context)
    - callback: Function called with each text chunk as it arrives (for /3 arity)
    - opts: Optional keyword list with the following options (for /4 arity):
      - `:provider` - The provider to use (`:anthropic` or `:openai`). Defaults to configured default.
      - `:model` - The model to use. Defaults to provider's default model.
      - `:api_key` - Custom API key. Defaults to application config.

  ## Returns
    - `{:ok, complete_response}` - Success with full AI response
    - `{:error, :provider_not_configured, message}` - Provider API key not configured
    - `{:error, error_type, message}` - Other errors (see Citadel.AI.Provider for error types)

  ## Examples

      # Stream to console with default provider
      Citadel.AI.Client.stream_message("Hello!", current_user, fn chunk ->
        IO.write(chunk)
        :ok
      end)

      # Stream to database with explicit provider
      Citadel.AI.Client.stream_message(
        "Write a poem",
        actor,
        [provider: :anthropic],
        fn chunk ->
          Message.upsert_response!(id: msg_id, text: chunk)
          :ok
        end
      )
  """
  @spec stream_message(String.t(), actor(), Provider.stream_callback()) ::
          {:ok, String.t()}
          | {:error, Provider.error_type() | :provider_not_configured, String.t()}
  def stream_message(message, actor, callback) when is_function(callback, 1) do
    stream_message(message, actor, [], callback)
  end

  @spec stream_message(String.t(), actor(), opts(), Provider.stream_callback()) ::
          {:ok, String.t()}
          | {:error, Provider.error_type() | :provider_not_configured, String.t()}
  def stream_message(message, actor, opts, callback) when is_function(callback, 1) do
    provider = Keyword.get(opts, :provider, Config.default_provider())

    with {:ok, api_key} <- get_api_key(provider, opts),
         {:ok, provider_config} <- build_provider_config(provider, api_key, opts),
         {:ok, provider_module} <- get_provider_module(provider) do
      provider_module.stream_message(message, actor, provider_config, callback)
    end
  end

  @doc """
  Streaming version that raises on error.

  Same as `stream_message/3` or `stream_message/4` but raises on error instead of
  returning error tuple.

  ## Examples

      # With default provider
      response = Citadel.AI.Client.stream_message!("Hello!", current_user, fn chunk ->
        IO.write(chunk)
        :ok
      end)

      # With explicit provider
      response = Citadel.AI.Client.stream_message!(
        "Hello!",
        current_user,
        [provider: :openai],
        fn chunk ->
          IO.write(chunk)
          :ok
        end
      )
  """
  @spec stream_message!(String.t(), actor(), Provider.stream_callback()) :: String.t()
  def stream_message!(message, actor, callback) when is_function(callback, 1) do
    case stream_message(message, actor, callback) do
      {:ok, response} -> response
      {:error, _type, message} -> raise RuntimeError, message
    end
  end

  @spec stream_message!(String.t(), actor(), opts(), Provider.stream_callback()) :: String.t()
  def stream_message!(message, actor, opts, callback) when is_function(callback, 1) do
    case stream_message(message, actor, opts, callback) do
      {:ok, response} -> response
      {:error, _type, message} -> raise RuntimeError, message
    end
  end

  @doc """
  Checks if a provider is available (configured with API key).

  ## Parameters
    - provider: The provider to check (`:anthropic` or `:openai`)

  ## Examples

      if Citadel.AI.Client.provider_available?(:anthropic) do
        # Use Anthropic
      else
        # Fall back to another provider
      end
  """
  @spec provider_available?(Config.provider()) :: boolean()
  def provider_available?(provider) do
    case Config.get_api_key(provider) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Lists all available (configured) providers.

  ## Examples

      Citadel.AI.Client.available_providers()
      # => [:anthropic, :openai]
  """
  @spec available_providers() :: [Config.provider()]
  def available_providers do
    Config.supported_providers()
    |> Enum.filter(&provider_available?/1)
  end

  @doc """
  Gets the default model for a provider.

  ## Parameters
    - provider: The provider (`:anthropic` or `:openai`)

  ## Examples

      Citadel.AI.Client.default_model(:anthropic)
      # => "claude-3-5-sonnet-20241022"

      Citadel.AI.Client.default_model(:openai)
      # => "gpt-4o"
  """
  @spec default_model(Config.provider()) :: String.t()
  def default_model(provider) do
    provider_module = Config.provider_module(provider)
    provider_module.default_model()
  end

  # Private helpers

  defp get_api_key(provider, opts) do
    case Keyword.get(opts, :api_key) do
      nil ->
        case Config.get_api_key(provider) do
          {:ok, api_key} ->
            {:ok, api_key}

          {:error, reason} ->
            {:error, :provider_not_configured, reason}
        end

      api_key when is_binary(api_key) ->
        {:ok, api_key}
    end
  end

  defp build_provider_config(provider, api_key, opts) do
    provider_module = Config.provider_module(provider)
    model = Keyword.get(opts, :model, provider_module.default_model())

    config = %{
      api_key: api_key,
      model: model
    }

    case provider_module.validate_config(config) do
      :ok -> {:ok, config}
      {:error, reason} -> {:error, :invalid_request_error, reason}
    end
  end

  defp get_provider_module(provider) do
    if Config.supported_provider?(provider) do
      {:ok, Config.provider_module(provider)}
    else
      {:error, :invalid_request_error, "Unsupported provider: #{inspect(provider)}"}
    end
  end
end
