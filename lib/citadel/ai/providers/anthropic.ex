defmodule Citadel.AI.Providers.Anthropic do
  @moduledoc """
  Anthropic (Claude) AI provider implementation.

  This module implements the Citadel.AI.Provider behavior for Anthropic's
  Claude models using the LangChain library.
  """

  @behaviour Citadel.AI.Provider

  alias Citadel.AI.Provider
  alias Citadel.AI.SchemaNormalizer
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

    chain =
      %{llm: model}
      |> LLMChain.new!()

    chain =
      if config[:tools] == false do
        chain
      else
        AshAi.setup_ash_ai(chain, actor: actor, otp_app: :citadel)
      end

    result =
      chain
      |> LLMChain.add_message(Message.new_user!(message))
      |> LLMChain.run()

    case result do
      {:ok, chain} ->
        extract_response(chain.last_message)

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
        extract_response(chain.last_message)

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
    error_type = Provider.classify_http_error(status)
    {:error, error_type, message}
  end

  def parse_error(%{status: status, body: body} = _response) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} ->
        message = extract_api_error_message(decoded, status)
        error_type = Provider.classify_http_error(status)
        {:error, error_type, message}

      {:error, _} ->
        error_type = Provider.classify_http_error(status)
        {:error, error_type, "API returned status #{status}: #{body}"}
    end
  end

  def parse_error(%{status: status}) when is_integer(status) do
    error_type = Provider.classify_http_error(status)
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
    "claude-sonnet-4-5"
  end

  @impl true
  def create_chain(actor, config, opts \\ []) do
    stream = Keyword.get(opts, :stream, false)

    model =
      ChatAnthropic.new!(%{
        model: config[:model] || default_model(),
        api_key: config.api_key,
        stream: stream
      })

    chain =
      %{llm: model}
      |> LLMChain.new!()

    # Add custom context if provided
    chain =
      case Keyword.get(opts, :custom_context) do
        nil -> chain
        context -> Map.put(chain, :custom_context, context)
      end

    # Setup AshAi if requested
    chain =
      if Keyword.get(opts, :setup_ash_ai, false) do
        ash_ai_opts =
          opts
          |> Keyword.get(:ash_ai_opts, [])
          |> Keyword.put(:actor, actor)

        chain
        |> AshAi.setup_ash_ai(ash_ai_opts)
        |> SchemaNormalizer.normalize_chain()
      else
        chain
      end

    {:ok, chain}
  rescue
    error ->
      {:error, :api_error, Exception.message(error)}
  end

  # Private helpers

  defp extract_response(%Message{content: response}) when is_binary(response) do
    {:ok, response}
  end

  defp extract_response(%Message{content: content_parts}) when is_list(content_parts) do
    text =
      content_parts
      |> Enum.filter(&match?(%{type: :text}, &1))
      |> Enum.map_join("", & &1.content)

    if text != "" do
      {:ok, text}
    else
      {:error, :api_error, "No text response from AI"}
    end
  end

  defp extract_response(_) do
    {:error, :api_error, "No response from AI"}
  end

  defp extract_api_error_message(%{"error" => %{"type" => type, "message" => message}}, _status) do
    "Anthropic API Error (#{type}): #{message}"
  end

  defp extract_api_error_message(%{"error" => %{"message" => message}}, _status) do
    "Anthropic API Error: #{message}"
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
