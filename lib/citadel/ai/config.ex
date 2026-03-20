defmodule Citadel.AI.Config do
  @moduledoc """
  Configuration management for AI providers.

  This module handles API key retrieval and provider configuration.
  It's designed to support both application-level API keys (current)
  and user-specific API keys (future enhancement).
  """

  @type provider :: :anthropic | :openai
  @type opts :: keyword()

  @doc """
  Gets the API key for a specific provider.

  ## Parameters
    - provider: The AI provider (:anthropic or :openai)
    - opts: Optional keyword list (reserved for future use with :user option)

  ## Returns
    - `{:ok, api_key}` if key is found
    - `{:error, reason}` if key is not configured

  ## Examples

      iex> Citadel.AI.Config.get_api_key(:anthropic)
      {:ok, "sk-ant-..."}

      # Future: Support for user-specific keys
      # iex> Citadel.AI.Config.get_api_key(:openai, user: %User{id: 123})
      # {:ok, "sk-..."}
  """
  @spec get_api_key(provider(), opts()) :: {:ok, String.t()} | {:error, String.t()}
  def get_api_key(provider, _opts \\ []) do
    config_key =
      case provider do
        :anthropic -> :anthropic_api_key
        :openai -> :openai_api_key
        _ -> nil
      end

    case config_key && Application.get_env(:citadel, Citadel.AI)[config_key] do
      nil ->
        {:error, "#{provider_name(provider)} API key not configured"}

      key when is_binary(key) ->
        {:ok, key}

      _ ->
        {:error, "Invalid #{provider_name(provider)} API key configuration"}
    end
  end

  @doc """
  Gets the API key for a provider, raises if not found.

  ## Parameters
    - provider: The AI provider (:anthropic or :openai)
    - opts: Optional keyword list

  ## Examples

      iex> Citadel.AI.Config.get_api_key!(:anthropic)
      "sk-ant-..."
  """
  @spec get_api_key!(provider(), opts()) :: String.t()
  def get_api_key!(provider, opts \\ []) do
    case get_api_key(provider, opts) do
      {:ok, key} -> key
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  Gets the default provider from configuration.

  ## Returns
    - The configured default provider atom (:anthropic or :openai)
    - Falls back to :anthropic if not configured

  ## Examples

      iex> Citadel.AI.Config.default_provider()
      :anthropic
  """
  @spec default_provider() :: provider()
  def default_provider do
    Application.get_env(:citadel, Citadel.AI)[:default_provider] || :anthropic
  end

  @doc """
  Gets the provider module for a given provider atom.

  In test environments, this can be overridden by setting the `:provider_overrides`
  config option to allow mocking of specific providers.

  ## Parameters
    - provider: The AI provider (:anthropic or :openai)

  ## Returns
    - The module implementing the provider behavior

  ## Examples

      iex> Citadel.AI.Config.provider_module(:anthropic)
      Citadel.AI.Providers.Anthropic

      # In test config:
      # config :citadel, Citadel.AI, provider_overrides: %{anthropic: Citadel.AI.MockProvider}
  """
  @spec provider_module(provider()) :: module()
  def provider_module(provider) do
    overrides = Application.get_env(:citadel, Citadel.AI)[:provider_overrides] || %{}

    case Map.get(overrides, provider) do
      nil ->
        case provider do
          :anthropic -> Citadel.AI.Providers.Anthropic
          :openai -> Citadel.AI.Providers.OpenAI
          _ -> raise ArgumentError, "Unknown provider: #{inspect(provider)}"
        end

      module ->
        module
    end
  end

  @doc """
  Lists all supported providers.

  ## Returns
    - List of provider atoms

  ## Examples

      iex> Citadel.AI.Config.supported_providers()
      [:anthropic, :openai]
  """
  @spec supported_providers() :: [provider()]
  def supported_providers do
    [:anthropic, :openai]
  end

  @doc """
  Checks if a provider is supported.

  ## Parameters
    - provider: The provider atom to check

  ## Examples

      iex> Citadel.AI.Config.supported_provider?(:anthropic)
      true

      iex> Citadel.AI.Config.supported_provider?(:unknown)
      false
  """
  @spec supported_provider?(provider()) :: boolean()
  def supported_provider?(provider) do
    provider in supported_providers()
  end

  @doc """
  Gets a human-readable name for a provider.

  ## Parameters
    - provider: The provider atom

  ## Examples

      iex> Citadel.AI.Config.provider_name(:anthropic)
      "Anthropic"

      iex> Citadel.AI.Config.provider_name(:openai)
      "OpenAI"
  """
  @spec provider_name(provider()) :: String.t()
  def provider_name(provider) do
    case provider do
      :anthropic -> "Anthropic"
      :openai -> "OpenAI"
      _ -> to_string(provider)
    end
  end

  @doc """
  Resolves the AI model configuration from the given options.

  Resolution priority:
  1. If `model_config_id` is provided, loads that specific ModelConfig
  2. If `workspace_id` is provided, returns the workspace's default ModelConfig
  3. Falls back to system defaults (provider from env, default model from provider module)

  Always returns a plain map with `:provider`, `:model`, `:temperature`, `:max_tokens` keys.
  """
  @spec resolve_model_config(keyword()) :: {:ok, map()} | {:error, term()}
  def resolve_model_config(opts \\ []) do
    cond do
      opts[:model_config_id] ->
        resolve_from_model_config(opts[:model_config_id])

      opts[:workspace_id] ->
        resolve_from_workspace_default(opts[:workspace_id])

      true ->
        {:ok, system_defaults()}
    end
  end

  defp resolve_from_model_config(model_config_id) do
    import Ecto.Query, only: [from: 2]

    case Citadel.Repo.one(from(mc in Citadel.Tasks.ModelConfig, where: mc.id == ^model_config_id)) do
      nil -> {:error, "ModelConfig not found"}
      config -> {:ok, model_config_to_map(config)}
    end
  end

  defp resolve_from_workspace_default(workspace_id) do
    case Citadel.Tasks.get_workspace_default_model_config(
           authorize?: false,
           tenant: workspace_id
         ) do
      {:ok, config} -> {:ok, model_config_to_map(config)}
      {:error, _} -> {:ok, system_defaults()}
    end
  end

  defp model_config_to_map(config) do
    %{
      provider: config.provider,
      model: config.model,
      temperature: config.temperature,
      max_tokens: config.max_tokens
    }
  end

  defp system_defaults do
    provider = default_provider()
    provider_mod = provider_module(provider)

    %{
      provider: provider,
      model: provider_mod.default_model(),
      temperature: 0.7,
      max_tokens: nil
    }
  end
end
