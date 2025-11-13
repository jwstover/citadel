defmodule Citadel.AI.Helpers do
  @moduledoc """
  Helper functions for AI integrations.

  This module provides utility functions for working with AI providers,
  particularly for integrations that need direct access to LangChain models
  (like AshAi).
  """

  alias Citadel.AI.Config
  alias LangChain.ChatModels.ChatAnthropic
  alias LangChain.ChatModels.ChatOpenAI

  @doc """
  Gets a configured LangChain model for the specified provider.

  This is useful for integrations that need direct access to a LangChain
  model, such as AshAi's prompt() function.

  ## Parameters
    - provider: The provider to use (optional, defaults to configured default)
    - opts: Optional keyword list with:
      - `:model` - Specific model to use
      - `:api_key` - Custom API key

  ## Examples

      # Get default provider's model
      model = Citadel.AI.Helpers.get_model()

      # Get specific provider's model
      model = Citadel.AI.Helpers.get_model(:openai)

      # Get specific provider with custom model
      model = Citadel.AI.Helpers.get_model(:anthropic, model: "claude-3-opus-20240229")
  """
  @spec get_model(Citadel.AI.Config.provider() | nil, keyword()) ::
          ChatAnthropic.t() | ChatOpenAI.t()
  def get_model(provider \\ nil, opts \\ []) do
    provider = provider || Config.default_provider()
    api_key = Keyword.get(opts, :api_key) || Config.get_api_key!(provider)

    case provider do
      :anthropic ->
        ChatAnthropic.new!(%{
          model: Keyword.get(opts, :model, Citadel.AI.default_model(:anthropic)),
          api_key: api_key
        })

      :openai ->
        ChatOpenAI.new!(%{
          model: Keyword.get(opts, :model, Citadel.AI.default_model(:openai)),
          api_key: api_key
        })

      _ ->
        raise ArgumentError, "Unsupported provider: #{inspect(provider)}"
    end
  end

  @doc """
  Gets a configured LangChain model, returns nil if provider not configured.

  Same as `get_model/2` but returns nil instead of raising if the provider
  is not configured.

  ## Examples

      case Citadel.AI.Helpers.get_model_if_available() do
        nil -> # No AI provider configured
        model -> # Use model
      end
  """
  @spec get_model_if_available(Citadel.AI.Config.provider() | nil, keyword()) ::
          ChatAnthropic.t() | ChatOpenAI.t() | nil
  def get_model_if_available(provider \\ nil, opts \\ []) do
    provider = provider || Config.default_provider()

    case Config.get_api_key(provider) do
      {:ok, api_key} ->
        opts = Keyword.put_new(opts, :api_key, api_key)
        get_model(provider, opts)

      {:error, _} ->
        nil
    end
  end
end
