defmodule CitadelAgent.Client do
  @moduledoc """
  HTTP client for communicating with the Citadel API.
  """

  require Logger

  def claim_task do
    case req_post("/api/agent/tasks/claim", %{}) do
      {:ok, %Req.Response{status: 200, body: %{"data" => data}}} ->
        {:ok, data}

      {:ok, %Req.Response{status: 204}} ->
        {:ok, nil}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def update_run(run_id, attrs) do
    case req_patch("/api/agent/runs/#{run_id}", attrs) do
      {:ok, %Req.Response{status: 200, body: %{"data" => run}}} ->
        {:ok, run}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def fetch_task_states do
    case req_get("/api/agent/task-states") do
      {:ok, %Req.Response{status: 200, body: %{"data" => states}}} ->
        {:ok, states}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def update_task_state(task_id, task_state_id) do
    case req_patch("/api/agent/tasks/#{task_id}", %{"task_state_id" => task_state_id}) do
      {:ok, %Req.Response{status: 200, body: %{"data" => task}}} ->
        {:ok, task}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp base_url, do: CitadelAgent.config(:citadel_url)
  defp api_key, do: CitadelAgent.config(:api_key)

  defp base_req do
    opts =
      Keyword.merge(
        [
          base_url: base_url(),
          headers: [
            {"authorization", "Bearer #{api_key()}"},
            {"content-type", "application/json"},
            {"accept", "application/json"}
          ]
        ],
        req_options()
      )

    Req.new(opts)
  end

  defp req_options do
    Application.get_env(:citadel_agent, :client_req_options, [])
  end

  defp req_get(path) do
    Req.get(base_req(), url: path)
  end

  defp req_post(path, body) do
    Req.post(base_req(), url: path, json: body)
  end

  defp req_patch(path, body) do
    Req.patch(base_req(), url: path, json: body)
  end
end
