defmodule Citadel.Agent.StreamParserTest do
  use ExUnit.Case, async: true

  alias Citadel.Agent.StreamParser

  describe "parse/1" do
    test "parses system init event" do
      json =
        Jason.encode!(%{
          "type" => "system",
          "subtype" => "init",
          "cwd" => "/some/path",
          "session_id" => "abc-123",
          "tools" => ["Bash", "Read", "Write"],
          "model" => "claude-opus-4-6[1m]"
        })

      assert %{
               type: :system,
               subtype: "init",
               session_id: "abc-123",
               tools: ["Bash", "Read", "Write"],
               model: "claude-opus-4-6[1m]"
             } = StreamParser.parse(json)
    end

    test "parses assistant event with text content" do
      json =
        Jason.encode!(%{
          "type" => "assistant",
          "message" => %{
            "model" => "claude-opus-4-6",
            "content" => [
              %{"type" => "text", "text" => "Hello! How can I help you today?"}
            ]
          },
          "session_id" => "abc-123"
        })

      assert %{
               type: :assistant,
               blocks: [%{type: :text, text: "Hello! How can I help you today?"}],
               model: "claude-opus-4-6",
               session_id: "abc-123"
             } = StreamParser.parse(json)
    end

    test "parses assistant event with tool_use content" do
      json =
        Jason.encode!(%{
          "type" => "assistant",
          "message" => %{
            "model" => "claude-opus-4-6",
            "content" => [
              %{
                "type" => "tool_use",
                "id" => "toolu_abc123",
                "name" => "Bash",
                "input" => %{"command" => "echo hello", "description" => "Print hello"}
              }
            ]
          },
          "session_id" => "abc-123"
        })

      assert %{
               type: :assistant,
               blocks: [
                 %{
                   type: :tool_use,
                   tool: "Bash",
                   input: %{"command" => "echo hello", "description" => "Print hello"},
                   id: "toolu_abc123"
                 }
               ]
             } = StreamParser.parse(json)
    end

    test "parses assistant event with mixed text and tool_use blocks" do
      json =
        Jason.encode!(%{
          "type" => "assistant",
          "message" => %{
            "model" => "claude-opus-4-6",
            "content" => [
              %{"type" => "text", "text" => "Let me check that."},
              %{
                "type" => "tool_use",
                "id" => "toolu_xyz",
                "name" => "Read",
                "input" => %{"file_path" => "/tmp/test.txt"}
              }
            ]
          },
          "session_id" => "abc-123"
        })

      result = StreamParser.parse(json)
      assert result.type == :assistant
      assert length(result.blocks) == 2
      assert Enum.at(result.blocks, 0).type == :text
      assert Enum.at(result.blocks, 1).type == :tool_use
      assert Enum.at(result.blocks, 1).tool == "Read"
    end

    test "parses user/tool_result event" do
      json =
        Jason.encode!(%{
          "type" => "user",
          "message" => %{
            "role" => "user",
            "content" => [
              %{
                "tool_use_id" => "toolu_abc123",
                "type" => "tool_result",
                "content" => "hello",
                "is_error" => false
              }
            ]
          },
          "session_id" => "abc-123",
          "tool_use_result" => %{
            "stdout" => "hello",
            "stderr" => "",
            "interrupted" => false
          }
        })

      assert %{
               type: :tool_result,
               results: [
                 %{
                   type: :tool_result,
                   tool_use_id: "toolu_abc123",
                   content: "hello",
                   is_error: false
                 }
               ],
               session_id: "abc-123",
               tool_use_result: %{"stdout" => "hello", "stderr" => "", "interrupted" => false}
             } = StreamParser.parse(json)
    end

    test "parses result event (success)" do
      json =
        Jason.encode!(%{
          "type" => "result",
          "subtype" => "success",
          "is_error" => false,
          "duration_ms" => 2109,
          "num_turns" => 1,
          "result" => "Hello! How can I help you today?",
          "stop_reason" => "end_turn",
          "session_id" => "abc-123",
          "total_cost_usd" => 0.047,
          "usage" => %{"input_tokens" => 3, "output_tokens" => 12}
        })

      assert %{
               type: :result,
               subtype: "success",
               is_error: false,
               result: "Hello! How can I help you today?",
               stop_reason: "end_turn",
               duration_ms: 2109,
               num_turns: 1,
               total_cost_usd: 0.047,
               session_id: "abc-123"
             } = StreamParser.parse(json)
    end

    test "parses result event (error)" do
      json =
        Jason.encode!(%{
          "type" => "result",
          "subtype" => "error",
          "is_error" => true,
          "result" => "Something went wrong",
          "stop_reason" => "error",
          "session_id" => "abc-123"
        })

      result = StreamParser.parse(json)
      assert result.type == :result
      assert result.subtype == "error"
      assert result.is_error == true
    end

    test "parses rate_limit_event" do
      json =
        Jason.encode!(%{
          "type" => "rate_limit_event",
          "rate_limit_info" => %{
            "status" => "allowed",
            "resetsAt" => 1_773_460_800,
            "rateLimitType" => "five_hour"
          },
          "session_id" => "abc-123"
        })

      assert %{
               type: :rate_limit_event,
               rate_limit_info: %{"status" => "allowed"},
               session_id: "abc-123"
             } = StreamParser.parse(json)
    end

    test "returns unknown for unrecognized event types" do
      json = Jason.encode!(%{"type" => "some_future_event", "data" => "value"})

      assert %{type: :unknown, raw: %{"type" => "some_future_event", "data" => "value"}} =
               StreamParser.parse(json)
    end

    test "returns error for invalid JSON" do
      assert %{type: :error, raw: "not valid json {"} = StreamParser.parse("not valid json {")
    end

    test "returns error for empty string" do
      assert %{type: :error, raw: ""} = StreamParser.parse("")
    end

    test "extracts parent_tool_use_id for assistant events" do
      json =
        Jason.encode!(%{
          "type" => "assistant",
          "parent_tool_use_id" => "toolu_parent_abc",
          "message" => %{
            "model" => "claude-opus-4-6",
            "content" => [
              %{"type" => "text", "text" => "Sub-agent working..."}
            ]
          },
          "session_id" => "sub-session"
        })

      result = StreamParser.parse(json)
      assert result.type == :assistant
      assert result.parent_tool_use_id == "toolu_parent_abc"
    end

    test "extracts parent_tool_use_id for tool_result events" do
      json =
        Jason.encode!(%{
          "type" => "user",
          "parent_tool_use_id" => "toolu_parent_xyz",
          "message" => %{
            "role" => "user",
            "content" => [
              %{
                "tool_use_id" => "toolu_sub_123",
                "type" => "tool_result",
                "content" => "result data"
              }
            ]
          },
          "session_id" => "sub-session"
        })

      result = StreamParser.parse(json)
      assert result.type == :tool_result
      assert result.parent_tool_use_id == "toolu_parent_xyz"
    end

    test "parent_tool_use_id is nil for top-level events" do
      json =
        Jason.encode!(%{
          "type" => "assistant",
          "message" => %{
            "model" => "claude-opus-4-6",
            "content" => [
              %{"type" => "text", "text" => "Hello"}
            ]
          },
          "session_id" => "abc-123"
        })

      result = StreamParser.parse(json)
      assert result.parent_tool_use_id == nil
    end

    test "tool_result block without content field preserves tool_use_id" do
      json =
        Jason.encode!(%{
          "type" => "user",
          "message" => %{
            "role" => "user",
            "content" => [
              %{
                "tool_use_id" => "toolu_no_content",
                "type" => "tool_result"
              }
            ]
          },
          "session_id" => "abc-123"
        })

      result = StreamParser.parse(json)
      assert result.type == :tool_result
      assert [%{tool_use_id: "toolu_no_content", content: nil}] = result.results
    end
  end
end
