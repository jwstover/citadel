defmodule Citadel.Agent.StreamParser do
  @moduledoc """
  Parses Claude Code `--output-format stream-json` lines into structured Elixir maps.

  Each line of stream-json output is a JSON object with a `"type"` field. This module
  decodes each line and normalizes it into a map with atom keys for the type.
  """

  @doc """
  Parses a single line of stream-json output into a structured map.

  Returns a map with `:type` as an atom and relevant fields extracted from the JSON.
  Unknown event types return `%{type: :unknown, raw: decoded_map}`.
  Invalid JSON returns `%{type: :error, raw: original_string}`.
  """
  def parse(line) when is_binary(line) do
    case Jason.decode(line) do
      {:ok, decoded} -> parse_event(decoded)
      {:error, _} -> %{type: :error, raw: line}
    end
  end

  defp parse_event(%{"type" => "system"} = event) do
    %{
      type: :system,
      subtype: event["subtype"],
      session_id: event["session_id"],
      tools: event["tools"],
      model: event["model"],
      tasks: event["tasks"]
    }
  end

  defp parse_event(%{"type" => "assistant", "message" => %{"content" => content}} = event) do
    blocks = Enum.map(content, &parse_content_block/1)

    %{
      type: :assistant,
      blocks: blocks,
      model: get_in(event, ["message", "model"]),
      session_id: event["session_id"]
    }
  end

  defp parse_event(%{"type" => "user", "message" => %{"content" => content}} = event) do
    results = Enum.map(content, &parse_tool_result_block/1)

    %{
      type: :tool_result,
      results: results,
      session_id: event["session_id"],
      tool_use_result: event["tool_use_result"]
    }
  end

  defp parse_event(%{"type" => "result"} = event) do
    %{
      type: :result,
      subtype: event["subtype"],
      result: event["result"],
      is_error: event["is_error"],
      stop_reason: event["stop_reason"],
      duration_ms: event["duration_ms"],
      num_turns: event["num_turns"],
      total_cost_usd: event["total_cost_usd"],
      usage: event["usage"],
      session_id: event["session_id"]
    }
  end

  defp parse_event(%{"type" => "rate_limit_event"} = event) do
    %{
      type: :rate_limit_event,
      rate_limit_info: event["rate_limit_info"],
      session_id: event["session_id"]
    }
  end

  defp parse_event(decoded) do
    %{type: :unknown, raw: decoded}
  end

  defp parse_content_block(%{"type" => "text", "text" => text}) do
    %{type: :text, text: text}
  end

  defp parse_content_block(%{"type" => "thinking", "thinking" => thinking}) do
    %{type: :thinking, text: thinking}
  end

  defp parse_content_block(%{"type" => "tool_use", "name" => name, "input" => input, "id" => id}) do
    %{type: :tool_use, tool: name, input: input, id: id}
  end

  defp parse_content_block(block) do
    %{type: :unknown, raw: block}
  end

  defp parse_tool_result_block(
         %{"type" => "tool_result", "tool_use_id" => id, "content" => content} = block
       ) do
    %{
      type: :tool_result,
      tool_use_id: id,
      content: content,
      is_error: Map.get(block, "is_error", false)
    }
  end

  defp parse_tool_result_block(block) do
    %{type: :unknown, raw: block}
  end
end
