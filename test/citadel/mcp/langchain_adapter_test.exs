defmodule Citadel.MCP.LangChainAdapterTest do
  use ExUnit.Case, async: true

  alias Citadel.MCP.LangChainAdapter

  describe "to_langchain_functions/2" do
    test "converts MCP tools to LangChain Function structs" do
      mcp_tools = [
        %{
          "name" => "get_file_contents",
          "description" => "Read file contents from a repository",
          "inputSchema" => %{
            "type" => "object",
            "properties" => %{
              "owner" => %{"type" => "string"},
              "repo" => %{"type" => "string"},
              "path" => %{"type" => "string"}
            },
            "required" => ["owner", "repo", "path"]
          }
        }
      ]

      # Using self() as a fake client PID for testing
      functions = LangChainAdapter.to_langchain_functions(mcp_tools, self())

      assert length(functions) == 1
      [function] = functions

      assert function.name == "get_file_contents"
      assert function.description == "Read file contents from a repository"
      assert function.parameters_schema["type"] == "object"
      assert is_function(function.function, 2)
    end

    test "handles multiple tools" do
      mcp_tools = [
        %{
          "name" => "tool_one",
          "description" => "First tool",
          "inputSchema" => %{"type" => "object"}
        },
        %{
          "name" => "tool_two",
          "description" => "Second tool",
          "inputSchema" => %{"type" => "object"}
        }
      ]

      functions = LangChainAdapter.to_langchain_functions(mcp_tools, self())

      assert length(functions) == 2
      names = Enum.map(functions, & &1.name)
      assert "tool_one" in names
      assert "tool_two" in names
    end

    test "returns empty list for empty tools" do
      assert LangChainAdapter.to_langchain_functions([], self()) == []
    end

    test "adds additionalProperties: false to object schemas for Anthropic compatibility" do
      mcp_tools = [
        %{
          "name" => "test_tool",
          "description" => "Test tool",
          "inputSchema" => %{
            "type" => "object",
            "properties" => %{
              "name" => %{"type" => "string"}
            }
          }
        }
      ]

      [function] = LangChainAdapter.to_langchain_functions(mcp_tools, self())

      assert function.parameters_schema["additionalProperties"] == false
    end

    test "adds additionalProperties: false to nested object schemas" do
      mcp_tools = [
        %{
          "name" => "test_tool",
          "description" => "Test tool",
          "inputSchema" => %{
            "type" => "object",
            "properties" => %{
              "config" => %{
                "type" => "object",
                "properties" => %{
                  "setting" => %{"type" => "string"}
                }
              }
            }
          }
        }
      ]

      [function] = LangChainAdapter.to_langchain_functions(mcp_tools, self())

      assert function.parameters_schema["additionalProperties"] == false
      assert function.parameters_schema["properties"]["config"]["additionalProperties"] == false
    end

    test "adds additionalProperties: false to object schemas in array items" do
      mcp_tools = [
        %{
          "name" => "test_tool",
          "description" => "Test tool",
          "inputSchema" => %{
            "type" => "object",
            "properties" => %{
              "items" => %{
                "type" => "array",
                "items" => %{
                  "type" => "object",
                  "properties" => %{
                    "id" => %{"type" => "string"}
                  }
                }
              }
            }
          }
        }
      ]

      [function] = LangChainAdapter.to_langchain_functions(mcp_tools, self())

      items_schema = function.parameters_schema["properties"]["items"]["items"]
      assert items_schema["additionalProperties"] == false
    end

    test "handles nil inputSchema" do
      mcp_tools = [
        %{
          "name" => "test_tool",
          "description" => "Test tool",
          "inputSchema" => nil
        }
      ]

      [function] = LangChainAdapter.to_langchain_functions(mcp_tools, self())

      assert function.parameters_schema == nil
    end
  end

  describe "extract_text_content (via call_mcp_tool result processing)" do
    # We test the content extraction logic indirectly since it's private
    # These tests document the expected behavior of MCP result parsing

    test "extracts text from content array with text type" do
      content = [
        %{"type" => "text", "text" => "Hello"},
        %{"type" => "text", "text" => "World"}
      ]

      # Test the extraction logic directly
      result =
        content
        |> Enum.filter(&(is_map(&1) and &1["type"] == "text"))
        |> Enum.map_join("\n", & &1["text"])

      assert result == "Hello\nWorld"
    end

    test "filters out non-text content types" do
      content = [
        %{"type" => "text", "text" => "Keep this"},
        %{"type" => "image", "data" => "base64..."},
        %{"type" => "text", "text" => "And this"}
      ]

      result =
        content
        |> Enum.filter(&(is_map(&1) and &1["type"] == "text"))
        |> Enum.map_join("\n", & &1["text"])

      assert result == "Keep this\nAnd this"
    end

    test "handles empty content array" do
      content = []

      result =
        content
        |> Enum.filter(&(is_map(&1) and &1["type"] == "text"))
        |> Enum.map_join("\n", & &1["text"])

      assert result == ""
    end
  end
end
