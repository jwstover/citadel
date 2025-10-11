defmodule Citadel.AI.Providers.Anthropic do
  @moduledoc """
  Anthropic (Claude) AI provider implementation.

  This module implements the Citadel.AI.Provider behavior for Anthropic's
  Claude models using the LangChain library.
  """

  @behaviour Citadel.AI.Provider

  alias LangChain.Chains.LLMChain
  alias LangChain.ChatModels.ChatAnthropic
  alias LangChain.Message

  @impl true
  def send_message(message, actor, config) do
    model =
      ChatAnthropic.new!(%{
        model: config[:model] || default_model(),
        api_key: config.api_key
      })

    result =
      %{llm: model}
      |> LLMChain.new!()
      |> AshAi.setup_ash_ai(actor: actor, otp_app: :citadel)
      |> LLMChain.add_message(Message.new_user!(message))
      |> LLMChain.run()

    case result do
      {:ok, chain} ->
        case chain.last_message do
          %Message{content: response} when is_binary(response) ->
            {:ok, response}

          _ ->
            {:error, :api_error, "No response from AI"}
        end

      {:error, %LLMChain{}} ->
        {:error, :api_error,
         "The AI service encountered an error processing your request. This may be due to tool configuration issues."}

      {:error, reason} ->
        parse_error(reason)
    end
  rescue
    error in [ArgumentError, RuntimeError] ->
      {:error, :api_error, Exception.message(error)}

    error ->
      {:error, :unknown_error, "#{inspect(error)}"}
  catch
    :exit, _reason ->
      {:error, :timeout_error, "Request timed out"}

    kind, reason ->
      {:error, :unknown_error, "#{kind}: #{inspect(reason)}"}
  end

  @impl true
  def stream_message(message, actor, config, callback) do
    model =
      ChatAnthropic.new!(%{
        model: config[:model] || default_model(),
        api_key: config.api_key,
        stream: true
      })

    result =
      %{llm: model}
      |> LLMChain.new!()
      |> AshAi.setup_ash_ai(actor: actor, otp_app: :citadel)
      |> LLMChain.add_message(Message.new_user!(message))
      |> LLMChain.add_callback(%{
        on_llm_new_delta: fn _model, delta ->
          if delta.content && delta.content != "" do
            callback.(delta.content)
          end
        end
      })
      |> LLMChain.run()

    case result do
      {:ok, chain} ->
        case chain.last_message do
          %Message{content: response} when is_binary(response) ->
            {:ok, response}

          _ ->
            {:error, :api_error, "No response from AI"}
        end

      {:error, %LLMChain{}} ->
        {:error, :api_error,
         "The AI service encountered an error processing your request. This may be due to tool configuration issues."}

      {:error, reason} ->
        parse_error(reason)
    end
  rescue
    error in [ArgumentError, RuntimeError] ->
      {:error, :api_error, Exception.message(error)}

    error ->
      {:error, :unknown_error, "#{inspect(error)}"}
  catch
    :exit, _reason ->
      {:error, :timeout_error, "Request timed out"}

    kind, reason ->
      {:error, :unknown_error, "#{kind}: #{inspect(reason)}"}
  end

  @impl true
  def parse_error(%{status: status, body: body} = _response) when is_map(body) do
    message = extract_api_error_message(body, status)
    error_type = Citadel.AI.Provider.classify_http_error(status)
    {:error, error_type, message}
  end

  def parse_error(%{status: status, body: body} = _response) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} ->
        message = extract_api_error_message(decoded, status)
        error_type = Citadel.AI.Provider.classify_http_error(status)
        {:error, error_type, message}

      {:error, _} ->
        error_type = Citadel.AI.Provider.classify_http_error(status)
        {:error, error_type, "API returned status #{status}: #{body}"}
    end
  end

  def parse_error(%{status: status}) when is_integer(status) do
    error_type = Citadel.AI.Provider.classify_http_error(status)
    message = default_error_message(status)
    {:error, error_type, message}
  end

  def parse_error(reason) when is_binary(reason) do
    {:error, :api_error, reason}
  end

  def parse_error(reason) do
    {:error, :unknown_error, "#{inspect(reason)}"}
  end

  @impl true
  def validate_config(%{api_key: api_key, model: model})
      when is_binary(api_key) and is_binary(model) do
    :ok
  end

  def validate_config(%{api_key: api_key}) when is_binary(api_key) do
    :ok
  end

  def validate_config(_config) do
    {:error, "Invalid Anthropic configuration: api_key is required"}
  end

  @impl true
  def default_model do
    "claude-3-5-sonnet-20241022"
  end

  # Private helpers

  defp extract_api_error_message(%{"error" => %{"message" => message}}, _status) do
    "Anthropic API Error: #{message}"
  end

  defp extract_api_error_message(%{"error" => %{"type" => type, "message" => message}}, _status) do
    "Anthropic API Error (#{type}): #{message}"
  end

  defp extract_api_error_message(%{"message" => message}, _status) do
    "API Error: #{message}"
  end

  defp extract_api_error_message(%{"error" => error}, status) when is_binary(error) do
    "API Error (#{status}): #{error}"
  end

  defp extract_api_error_message(_body, status) do
    default_error_message(status)
  end

  defp default_error_message(400) do
    "Invalid request (400). The tools configuration may be too complex for the API."
  end

  defp default_error_message(401) do
    "Authentication failed (401). Please check your API key."
  end

  defp default_error_message(429) do
    "Rate limit exceeded (429). Please try again later."
  end

  defp default_error_message(500) do
    "Server error (500). Please try again later."
  end

  defp default_error_message(status) do
    "API returned status #{status}"
  end
end
