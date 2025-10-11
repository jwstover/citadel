defmodule Citadel.AI do
  @moduledoc """
  AI functionality for Citadel.

  This module provides the main interface for AI-powered features in Citadel,
  including chat interactions and intelligent task management.

  ## Configuration

  Configure AI providers in your runtime.exs:

      config :citadel, Citadel.AI,
        anthropic_api_key: System.get_env("ANTHROPIC_API_KEY"),
        openai_api_key: System.get_env("OPENAI_API_KEY"),
        default_provider: :anthropic

  ## Usage

  Send messages to AI providers:

      # Using default provider
      Citadel.AI.send_message("Hello!", current_user)

      # Using specific provider
      Citadel.AI.send_message("Hello!", current_user, provider: :openai)

  Check provider availability:

      if Citadel.AI.provider_available?(:anthropic) do
        # Use Anthropic
      end

  ## Supported Providers

  - `:anthropic` - Anthropic's Claude models
  - `:openai` - OpenAI's GPT models

  ## Future Enhancements

  This module is designed to support:
  - User-provided API keys (stored securely in database)
  - Per-user provider preferences
  - Custom model selection per user
  - Streaming responses
  - Conversation history management
  """

  # Delegate core functionality to Client
  defdelegate send_message(message, actor, opts \\ []), to: Citadel.AI.Client
  defdelegate send_message!(message, actor, opts \\ []), to: Citadel.AI.Client
  defdelegate provider_available?(provider), to: Citadel.AI.Client
  defdelegate available_providers(), to: Citadel.AI.Client
  defdelegate default_model(provider), to: Citadel.AI.Client

  # Delegate configuration management to Config
  defdelegate default_provider(), to: Citadel.AI.Config
  defdelegate supported_providers(), to: Citadel.AI.Config
  defdelegate provider_name(provider), to: Citadel.AI.Config

  @doc """
  Checks if AI functionality is available.

  Returns true if at least one provider is configured with an API key.

  ## Examples

      if Citadel.AI.available?() do
        # Show AI features
      else
        # Hide AI features or show setup instructions
      end
  """
  @spec available?() :: boolean()
  def available? do
    available_providers() != []
  end

  @doc """
  Gets a user-friendly error message for display.

  ## Parameters
    - error_type: The error type returned from send_message
    - message: The detailed error message

  ## Examples

      case Citadel.AI.send_message("Hello", user) do
        {:ok, response} -> response
        {:error, type, message} ->
          Citadel.AI.format_error(type, message)
      end
  """
  @spec format_error(Citadel.AI.Provider.error_type(), String.t()) :: String.t()
  def format_error(:provider_not_configured, message) do
    "AI provider not configured: #{message}"
  end

  def format_error(error_type, message) do
    Citadel.AI.Provider.format_error(error_type, message)
  end
end
