defmodule Citadel.MCP.LangChainAdapter do
  @moduledoc """
  Converts MCP tools to LangChain.Function structs.

  This adapter bridges the gap between hermes_mcp tool definitions and
  LangChain's function calling interface, allowing GitHub MCP tools to
  be used in AI chat conversations.
  """

  alias Citadel.AI.SchemaNormalizer
  alias Hermes.Client.Base, as: HermesBase
  alias LangChain.Function

  @doc """
  Converts a list of MCP tools to LangChain Function structs.

  Each tool's callback is configured to call the MCP client with the
  tool name and arguments.

  ## Parameters
    - mcp_tools: List of MCP tool definitions from `Hermes.Client.list_tools/1`
    - client_pid: PID of the MCP client to use for tool calls

  ## Returns
    List of `LangChain.Function` structs ready to add to an LLMChain
  """
  def to_langchain_functions(mcp_tools, client_pid) when is_list(mcp_tools) do
    Enum.map(mcp_tools, &to_langchain_function(&1, client_pid))
  end

  defp to_langchain_function(tool, client_pid) do
    Function.new!(%{
      name: tool["name"],
      description: tool["description"],
      parameters_schema: SchemaNormalizer.normalize_schema(tool["inputSchema"]),
      function: fn args, _context ->
        call_mcp_tool(client_pid, tool["name"], args)
      end
    })
  end

  @doc """
  Calls an MCP tool and returns the result formatted for LangChain.

  ## Returns
    - String content for successful calls
    - Error message string for failures
  """
  def call_mcp_tool(client_pid, name, args) do
    case HermesBase.call_tool(client_pid, name, args, []) do
      {:ok, %{result: %{"content" => content}}} ->
        extract_text_content(content)

      {:ok, %{result: result}} when is_map(result) ->
        Jason.encode!(result)

      {:ok, %{result: result}} ->
        to_string(result)

      {:error, %{message: message}} ->
        "Error: #{message}"

      {:error, error} ->
        "Error: #{inspect(error)}"
    end
  end

  defp extract_text_content(content) when is_list(content) do
    content
    |> Enum.filter(&(is_map(&1) and &1["type"] == "text"))
    |> Enum.map_join("\n", & &1["text"])
  end

  defp extract_text_content(content) when is_binary(content), do: content
  defp extract_text_content(_), do: ""
end
