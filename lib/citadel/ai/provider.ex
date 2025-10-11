defmodule Citadel.AI.Provider do
  @moduledoc """
  Behavior for AI provider implementations.

  Any module implementing this behavior can be used as an AI provider
  in the Citadel application. This enables support for multiple LLM
  providers (Anthropic, OpenAI, etc.) with a common interface.
  """

  @type error_type ::
          :authentication_error
          | :rate_limit_error
          | :invalid_request_error
          | :api_error
          | :timeout_error
          | :unknown_error

  @type config :: %{
          required(:api_key) => String.t(),
          required(:model) => String.t(),
          optional(atom()) => any()
        }

  @type actor :: struct() | nil

  @type stream_callback :: (String.t() -> :ok)

  @doc """
  Sends a message to the AI provider and returns the response.

  ## Parameters
    - message: The user message to send
    - actor: The current user/actor making the request
    - config: Provider-specific configuration including API key

  ## Returns
    - `{:ok, response_content}` on success
    - `{:error, error_type, message}` on failure
  """
  @callback send_message(String.t(), actor(), config()) ::
              {:ok, String.t()} | {:error, error_type(), String.t()}

  @doc """
  Streams a message to the AI provider, calling the callback for each chunk.

  The callback receives text deltas as they arrive. After streaming completes,
  the function returns the complete final message.

  ## Parameters
    - message: The user message to send
    - actor: The current user/actor making the request
    - config: Provider-specific configuration including API key
    - callback: Function called with each text chunk as it arrives

  ## Returns
    - `{:ok, complete_response}` on success with full message
    - `{:error, error_type, message}` on failure
  """
  @callback stream_message(String.t(), actor(), config(), stream_callback()) ::
              {:ok, String.t()} | {:error, error_type(), String.t()}

  @doc """
  Parses provider-specific errors into standardized error types.

  ## Parameters
    - error: The error returned from the provider's API

  ## Returns
    - `{:error, error_type, message}` tuple with standardized error type
  """
  @callback parse_error(any()) :: {:error, error_type(), String.t()}

  @doc """
  Validates the provider configuration.

  ## Parameters
    - config: The provider configuration to validate

  ## Returns
    - `:ok` if configuration is valid
    - `{:error, reason}` if configuration is invalid
  """
  @callback validate_config(config()) :: :ok | {:error, String.t()}

  @doc """
  Returns the default model name for this provider.
  """
  @callback default_model() :: String.t()

  @doc """
  Helper function to classify HTTP status codes into error types.
  """
  @spec classify_http_error(integer()) :: error_type()
  def classify_http_error(status) do
    case status do
      401 -> :authentication_error
      429 -> :rate_limit_error
      400 -> :invalid_request_error
      500 -> :api_error
      _ -> :api_error
    end
  end

  @doc """
  Formats an error message with consistent structure.
  """
  @spec format_error(error_type(), String.t()) :: String.t()
  def format_error(error_type, message) do
    prefix =
      case error_type do
        :authentication_error -> "Authentication failed"
        :rate_limit_error -> "Rate limit exceeded"
        :invalid_request_error -> "Invalid request"
        :api_error -> "API error"
        :timeout_error -> "Request timed out"
        :unknown_error -> "Unknown error"
      end

    "#{prefix}: #{message}"
  end
end
