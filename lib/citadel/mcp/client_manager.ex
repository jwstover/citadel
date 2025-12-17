defmodule Citadel.MCP.ClientManager do
  @moduledoc """
  Manages MCP client lifecycles for workspaces with GitHub connections.

  This module provides a simple API for getting GitHub MCP tools for a workspace.
  It handles:
  - Lazy client initialization (starts on first request)
  - Client reuse via Registry lookup
  - Client cleanup when connections are deleted

  ## Usage

      case Citadel.MCP.ClientManager.get_tools(workspace_id) do
        {:ok, tools} -> # List of LangChain.Function structs
        {:error, :no_connection} -> # No GitHub connection for workspace
        {:error, reason} -> # Other error
      end
  """

  require Logger

  alias Citadel.MCP.GitHubClient
  alias Citadel.MCP.LangChainAdapter
  alias Hermes.Client.Base, as: HermesBase

  @registry Citadel.MCP.ClientRegistry
  @supervisor Citadel.MCP.ClientSupervisor

  @doc """
  Gets LangChain-compatible tools for a workspace's GitHub connection.

  Returns `{:ok, tools}` with a list of LangChain.Function structs if the
  workspace has a GitHub connection configured, or `{:error, reason}` if not.
  """
  def get_tools(workspace_id) when is_binary(workspace_id) do
    with {:ok, supervisor_pid} <- get_or_start_client(workspace_id),
         {:ok, client_pid} <- get_client_pid(supervisor_pid),
         {:ok, tools} <- list_tools_safely(client_pid) do
      functions = LangChainAdapter.to_langchain_functions(tools, client_pid)
      {:ok, functions}
    else
      {:error, :no_connection} = error ->
        error

      {:error, reason} ->
        Logger.warning(
          "Failed to get MCP tools for workspace #{workspace_id}: #{inspect(reason)}"
        )

        {:error, reason}

      error ->
        Logger.warning("Unexpected error getting MCP tools: #{inspect(error)}")
        {:error, :unexpected_error}
    end
  end

  def get_tools(nil), do: {:error, :no_workspace}

  @doc """
  Stops the MCP client for a workspace.

  Call this when a GitHub connection is deleted to clean up resources.
  """
  def stop_client(workspace_id) when is_binary(workspace_id) do
    case Registry.lookup(@registry, workspace_id) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(@supervisor, pid)
        :ok

      [] ->
        :ok
    end
  end

  def stop_client(_), do: :ok

  defp get_or_start_client(workspace_id) do
    case Registry.lookup(@registry, workspace_id) do
      [{pid, _}] ->
        if Process.alive?(pid) do
          {:ok, pid}
        else
          start_client(workspace_id)
        end

      [] ->
        start_client(workspace_id)
    end
  end

  defp start_client(workspace_id) do
    with {:ok, connection} <- get_github_connection(workspace_id) do
      pat = connection.pat_encrypted

      opts = [
        transport:
          {:streamable_http,
           base_url: "https://api.githubcopilot.com",
           mcp_path: "/mcp/",
           headers: %{"Authorization" => "Bearer #{pat}"}},
        name: {:via, Registry, {@registry, workspace_id}},
        transport_name: {:via, Registry, {@registry, "#{workspace_id}_transport"}}
      ]

      child_spec =
        GitHubClient.child_spec(opts)
        |> Map.put(:id, {:github_mcp, workspace_id})
        |> Map.put(:restart, :temporary)

      case DynamicSupervisor.start_child(@supervisor, child_spec) do
        {:ok, pid} ->
          {:ok, pid}

        {:error, {:already_started, pid}} ->
          {:ok, pid}

        {:error, reason} ->
          Logger.error(
            "Failed to start MCP client for workspace #{workspace_id}: #{inspect(reason)}"
          )

          {:error, reason}
      end
    end
  end

  defp get_github_connection(workspace_id) do
    case Citadel.Integrations.get_workspace_github_connection(workspace_id,
           tenant: workspace_id,
           authorize?: false,
           not_found_error?: false
         ) do
      {:ok, nil} -> {:error, :no_connection}
      {:ok, connection} -> {:ok, connection}
      {:error, _} = error -> error
    end
  end

  defp get_client_pid(supervisor_pid) do
    supervisor_pid
    |> Supervisor.which_children()
    |> find_client_child()
  end

  defp find_client_child(children) when is_list(children) do
    case Enum.find(children, fn {id, _, _, _} -> id == Hermes.Client.Base end) do
      {Hermes.Client.Base, pid, _, _} when is_pid(pid) -> {:ok, pid}
      _ -> {:error, :client_not_found}
    end
  end

  defp find_client_child(_), do: {:error, :supervisor_error}

  defp list_tools_safely(client_pid) do
    case HermesBase.list_tools(client_pid, []) do
      {:ok, %{result: %{"tools" => tools}}} ->
        {:ok, tools}

      {:ok, other} ->
        Logger.warning("Unexpected list_tools response: #{inspect(other)}")
        {:error, :unexpected_response}

      {:error, reason} ->
        {:error, reason}
    end
  catch
    :exit, reason ->
      Logger.warning("MCP client exited while listing tools: #{inspect(reason)}")
      {:error, {:client_exit, reason}}
  end
end
