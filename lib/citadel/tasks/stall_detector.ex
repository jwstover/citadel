defmodule Citadel.Tasks.StallDetector do
  @moduledoc """
  GenServer that monitors active agent runs for stall conditions.

  Maintains an in-memory tracker of running agent runs and their last activity
  timestamps. Periodically checks for stalled runs and transitions them through:

      nil → :suspect → :stalled → :timed_out

  Timed-out runs are automatically cancelled.

  Activity is recorded via `record_activity/1`, which is called from the agent
  channel and API controller whenever stream output or API calls are received.
  """

  use GenServer

  require Ash.Query
  require Logger

  alias Citadel.Tasks

  @default_check_interval :timer.seconds(60)
  @default_suspect_threshold 3 * 60
  @default_stall_threshold 10 * 60
  @default_timeout_threshold 30 * 60
  @default_db_debounce_interval 30

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Records activity for an agent run, resetting its stall timer.

  Updates the in-memory tracker immediately and schedules a debounced DB write
  of `last_activity_at` (at most once per 30 seconds per run).
  """
  def record_activity(agent_run_id) do
    GenServer.cast(__MODULE__, {:record_activity, agent_run_id})
  end

  @doc false
  def record_activity(server, agent_run_id) do
    GenServer.cast(server, {:record_activity, agent_run_id})
  end

  @doc false
  def get_tracker(server \\ __MODULE__) do
    GenServer.call(server, :get_tracker)
  end

  @impl true
  def init(opts) do
    state = %{
      opts: opts,
      tracker: %{},
      last_db_update: %{},
      subscribed_topics: MapSet.new()
    }

    state = seed_running_runs(state)

    check_interval = config(opts, :check_interval, @default_check_interval)
    Process.send_after(self(), :check_stalls, check_interval)

    {:ok, state}
  end

  @impl true
  def handle_call(:get_tracker, _from, state) do
    {:reply, state.tracker, state}
  end

  @impl true
  def handle_cast({:record_activity, run_id}, state) do
    now = DateTime.utc_now()

    new_state =
      if Map.has_key?(state.tracker, run_id) do
        state
        |> put_in([:tracker, run_id, :last_activity_at], now)
        |> maybe_schedule_db_update(run_id, now)
      else
        case fetch_run_info(run_id) do
          {:ok, run_info} ->
            state
            |> subscribe_to_run_topic(run_info.task_id)
            |> put_in([:tracker, run_id], %{
              last_activity_at: now,
              task_id: run_info.task_id,
              workspace_id: run_info.workspace_id,
              stall_status: nil
            })
            |> maybe_schedule_db_update(run_id, now)

          _ ->
            state
        end
      end

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:check_stalls, state) do
    now = DateTime.utc_now()
    opts = state.opts

    suspect_threshold = config(opts, :suspect_threshold, @default_suspect_threshold)
    stall_threshold = config(opts, :stall_threshold, @default_stall_threshold)
    timeout_threshold = config(opts, :timeout_threshold, @default_timeout_threshold)

    new_tracker =
      Enum.reduce(state.tracker, %{}, fn {run_id, info}, acc ->
        silence_seconds = DateTime.diff(now, info.last_activity_at, :second)

        new_stall_status =
          cond do
            silence_seconds > timeout_threshold -> :timed_out
            silence_seconds > stall_threshold -> :stalled
            silence_seconds > suspect_threshold -> :suspect
            true -> nil
          end

        if new_stall_status != info.stall_status do
          send(
            self(),
            {:apply_stall_status, run_id, info.workspace_id, new_stall_status, now,
             info.last_activity_at}
          )
        end

        if new_stall_status == :timed_out do
          acc
        else
          Map.put(acc, run_id, Map.put(info, :stall_status, new_stall_status))
        end
      end)

    check_interval = config(opts, :check_interval, @default_check_interval)
    Process.send_after(self(), :check_stalls, check_interval)

    {:noreply, %{state | tracker: new_tracker}}
  end

  def handle_info(
        {:apply_stall_status, run_id, workspace_id, new_stall_status, now, last_activity_at},
        state
      ) do
    silence_seconds = DateTime.diff(now, last_activity_at, :second)

    Logger.info(
      "StallDetector: run #{run_id} stall_status → #{inspect(new_stall_status)} " <>
        "(silent for #{silence_seconds}s)"
    )

    Tasks.update_agent_run_stall_status!(run_id, %{stall_status: new_stall_status},
      authorize?: false,
      tenant: workspace_id
    )

    if new_stall_status == :timed_out do
      cancel_timed_out_run(run_id, workspace_id)
    end

    {:noreply, state}
  rescue
    err ->
      Logger.error(
        "StallDetector: failed to apply stall status for run #{run_id}: #{inspect(err)}"
      )

      {:noreply, state}
  end

  def handle_info({:update_last_activity, run_id, now, workspace_id}, state) do
    Tasks.update_agent_run_stall_status!(run_id, %{last_activity_at: now},
      authorize?: false,
      tenant: workspace_id
    )

    {:noreply, state}
  rescue
    _ -> {:noreply, state}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{
          topic: "tasks:agent_runs:" <> _,
          payload: %{data: %{id: run_id, status: status}}
        },
        state
      )
      when status in [:completed, :failed, :cancelled] do
    {:noreply, %{state | tracker: Map.delete(state.tracker, run_id)}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp seed_running_runs(state) do
    running_runs =
      Citadel.Tasks.AgentRun
      |> Ash.Query.filter(status == :running)
      |> Ash.Query.select([
        :id,
        :task_id,
        :workspace_id,
        :last_activity_at,
        :stall_status,
        :inserted_at
      ])
      |> Ash.read!(authorize?: false)

    now = DateTime.utc_now()

    Enum.reduce(running_runs, state, fn run, acc ->
      last_activity = run.last_activity_at || run.inserted_at || now

      acc
      |> subscribe_to_run_topic(run.task_id)
      |> put_in([:tracker, run.id], %{
        last_activity_at: last_activity,
        task_id: run.task_id,
        workspace_id: run.workspace_id,
        stall_status: run.stall_status
      })
    end)
  end

  defp fetch_run_info(run_id) do
    case Citadel.Tasks.AgentRun
         |> Ash.Query.filter(id == ^run_id)
         |> Ash.Query.select([:id, :task_id, :workspace_id])
         |> Ash.read_one(authorize?: false) do
      {:ok, %{task_id: task_id, workspace_id: workspace_id}} ->
        {:ok, %{task_id: task_id, workspace_id: workspace_id}}

      _ ->
        :error
    end
  end

  defp subscribe_to_run_topic(state, task_id) do
    topic = "tasks:agent_runs:#{task_id}"

    if MapSet.member?(state.subscribed_topics, topic) do
      state
    else
      CitadelWeb.Endpoint.subscribe(topic)
      %{state | subscribed_topics: MapSet.put(state.subscribed_topics, topic)}
    end
  end

  defp maybe_schedule_db_update(state, run_id, now) do
    debounce = config(state.opts, :db_debounce_interval, @default_db_debounce_interval)
    last_update = Map.get(state.last_db_update, run_id)

    should_update =
      is_nil(last_update) or DateTime.diff(now, last_update, :second) >= debounce

    if should_update do
      info = Map.get(state.tracker, run_id)

      if info do
        send(self(), {:update_last_activity, run_id, now, info.workspace_id})
      end

      %{state | last_db_update: Map.put(state.last_db_update, run_id, now)}
    else
      state
    end
  end

  defp cancel_timed_out_run(run_id, workspace_id) do
    case Tasks.get_agent_run(run_id, authorize?: false, tenant: workspace_id) do
      {:ok, run} when run.status in [:pending, :running] ->
        case Tasks.cancel_agent_run(run, authorize?: false, tenant: workspace_id) do
          {:ok, _} ->
            Logger.info("StallDetector: cancelled timed-out run #{run_id}")

          {:error, err} ->
            Logger.warning("StallDetector: failed to cancel run #{run_id}: #{inspect(err)}")
        end

      _ ->
        :ok
    end
  end

  defp config(opts, key, default) do
    app_config = Application.get_env(:citadel, __MODULE__, [])
    Keyword.get(opts, key, Keyword.get(app_config, key, default))
  end
end
