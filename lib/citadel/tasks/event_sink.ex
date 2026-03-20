defmodule Citadel.Tasks.EventSink do
  @moduledoc """
  GenServer that subscribes to agent-related PubSub topics and automatically
  persists events to the database as AgentRunEvent records.

  Subscribes to:
  - `tasks:agent_activity` — meta topic announcing new runs (static subscription)
  - `agent_run_output:{run_id}` — stream output from agents (dynamic)
  - `tasks:agent_runs:{task_id}` — run status changes (dynamic)
  - `tasks:refinement:{run_id}` — refinement cycle events (dynamic)

  Events are buffered in memory and flushed to the database in batches every
  `@flush_interval` ms or when the buffer reaches `@flush_threshold` events.
  """

  use GenServer

  require Ash.Query
  require Logger

  @flush_interval :timer.seconds(2)
  @flush_threshold 50

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    Phoenix.PubSub.subscribe(Citadel.PubSub, "tasks:agent_activity")

    state = %{
      opts: opts,
      buffer: [],
      seen_dedup_keys: MapSet.new(),
      timer_ref: schedule_flush(opts),
      run_info: %{},
      subscribed_topics: MapSet.new(["tasks:agent_activity"])
    }

    {:ok, seed_running_runs(state)}
  end

  @impl true
  def handle_info(:flush, state) do
    new_state = flush_buffer(state)
    {:noreply, %{new_state | timer_ref: schedule_flush(state.opts)}}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{
          topic: "tasks:agent_activity",
          payload: %{run_id: run_id, task_id: task_id, workspace_id: workspace_id}
        },
        state
      ) do
    {:noreply, subscribe_to_run(state, run_id, task_id, workspace_id)}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{
          topic: "agent_run_output:" <> run_id,
          event: "stream_event",
          payload: %{event: event_data}
        },
        state
      ) do
    if significant_stream_event?(event_data) do
      dedup_key = content_hash(run_id, :stream_output, event_data)

      event =
        build_event(
          run_id,
          state,
          :stream_output,
          stream_message(event_data),
          event_data,
          dedup_key
        )

      {:noreply, maybe_buffer(state, event)}
    else
      {:noreply, state}
    end
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{
          topic: "agent_run_output:" <> run_id,
          event: "stream_complete"
        },
        state
      ) do
    dedup_key = content_hash(run_id, :stream_output, :complete)

    event =
      build_event(run_id, state, :stream_output, "Stream completed", %{complete: true}, dedup_key)

    {:noreply, maybe_buffer(state, event)}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{
          topic: "tasks:agent_runs:" <> _,
          event: "update_stall_status",
          payload: %{data: %{id: run_id, stall_status: stall_status}}
        },
        state
      )
      when not is_nil(stall_status) do
    message = "Stall detected: status changed to #{stall_status}"
    dedup_key = content_hash(run_id, :stall_detected, stall_status)

    event =
      build_event(
        run_id,
        state,
        :stall_detected,
        message,
        %{stall_status: stall_status},
        dedup_key
      )

    {:noreply, maybe_buffer(state, event)}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{
          topic: "tasks:agent_runs:" <> _,
          event: action,
          payload: %{data: %{id: run_id, status: status}}
        },
        state
      )
      when action in ["update", "cancel"] do
    message = "Run status changed to #{status}"
    dedup_key = content_hash(run_id, :status_change, status)
    event = build_event(run_id, state, :status_change, message, %{status: status}, dedup_key)
    {:noreply, maybe_buffer(state, event)}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{
          topic: "tasks:refinement:" <> run_id,
          event: "create",
          payload: %{data: cycle}
        },
        state
      ) do
    message = "Refinement cycle started (max #{cycle.max_iterations} iterations)"
    dedup_key = content_hash(run_id, :refinement_started, cycle.id)

    event =
      build_event(
        run_id,
        state,
        :refinement_started,
        message,
        %{
          cycle_id: cycle.id,
          max_iterations: cycle.max_iterations
        },
        dedup_key
      )

    {:noreply, maybe_buffer(state, event)}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{
          topic: "tasks:refinement:" <> run_id,
          event: action,
          payload: %{data: cycle}
        },
        state
      )
      when action in ["complete", "fail"] do
    message = "Refinement cycle finished with status #{cycle.status}"
    dedup_key = content_hash(run_id, :refinement_completed, {cycle.id, cycle.status})

    event =
      build_event(
        run_id,
        state,
        :refinement_completed,
        message,
        %{
          cycle_id: cycle.id,
          status: cycle.status,
          final_score: cycle.final_score
        },
        dedup_key
      )

    {:noreply, maybe_buffer(state, event)}
  end

  def handle_info(
        %{
          event: "iteration_created",
          iteration: %{number: number, score: score, feedback: feedback, status: status}
        } = payload,
        state
      ) do
    run_id = Map.get(payload, :run_id)

    if run_id && Map.has_key?(state.run_info, run_id) do
      message = "Refinement iteration #{number} completed (score: #{score})"
      dedup_key = content_hash(run_id, :refinement_iteration, number)

      event =
        build_event(
          run_id,
          state,
          :refinement_iteration,
          message,
          %{
            iteration_number: number,
            score: score,
            feedback: feedback,
            status: status
          },
          dedup_key
        )

      {:noreply, maybe_buffer(state, event)}
    else
      {:noreply, state}
    end
  end

  def handle_info(
        %{event: "cycle_completed", status: status, final_score: final_score} = payload,
        state
      ) do
    run_id = Map.get(payload, :run_id)

    if run_id && Map.has_key?(state.run_info, run_id) do
      message = "Refinement cycle completed with status #{status}"
      dedup_key = content_hash(run_id, :refinement_completed, {status, final_score})

      event =
        build_event(
          run_id,
          state,
          :refinement_completed,
          message,
          %{
            status: status,
            final_score: final_score
          },
          dedup_key
        )

      {:noreply, maybe_buffer(state, event)}
    else
      {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    flush_buffer(state)
    :ok
  end

  defp seed_running_runs(state) do
    running_runs =
      Citadel.Tasks.AgentRun
      |> Ash.Query.filter(status == :running)
      |> Ash.Query.select([:id, :task_id, :workspace_id])
      |> Ash.read!(authorize?: false)

    Enum.reduce(running_runs, state, fn run, acc ->
      subscribe_to_run(acc, run.id, run.task_id, run.workspace_id)
    end)
  end

  defp subscribe_to_run(state, run_id, task_id, workspace_id) do
    state
    |> put_run_info(run_id, task_id, workspace_id)
    |> maybe_subscribe("agent_run_output:#{run_id}")
    |> maybe_subscribe("tasks:agent_runs:#{task_id}")
    |> maybe_subscribe("tasks:refinement:#{run_id}")
  end

  defp put_run_info(state, run_id, task_id, workspace_id) do
    %{
      state
      | run_info: Map.put(state.run_info, run_id, %{task_id: task_id, workspace_id: workspace_id})
    }
  end

  defp maybe_subscribe(state, topic) do
    if MapSet.member?(state.subscribed_topics, topic) do
      state
    else
      Phoenix.PubSub.subscribe(Citadel.PubSub, topic)
      %{state | subscribed_topics: MapSet.put(state.subscribed_topics, topic)}
    end
  end

  defp build_event(run_id, state, event_type, message, metadata, dedup_key) do
    workspace_id =
      case Map.get(state.run_info, run_id) do
        %{workspace_id: wid} -> wid
        nil -> nil
      end

    %{
      run_id: run_id,
      workspace_id: workspace_id,
      event_type: event_type,
      message: message,
      metadata: metadata,
      dedup_key: dedup_key
    }
  end

  defp content_hash(run_id, event_type, content) do
    hash = :erlang.phash2({run_id, event_type, content})
    "#{run_id}:#{event_type}:#{hash}"
  end

  defp maybe_buffer(state, %{workspace_id: nil}), do: state

  defp maybe_buffer(state, event) do
    if MapSet.member?(state.seen_dedup_keys, event.dedup_key) do
      state
    else
      new_buffer = [event | state.buffer]
      new_seen = MapSet.put(state.seen_dedup_keys, event.dedup_key)

      new_state = %{state | buffer: new_buffer, seen_dedup_keys: new_seen}

      if length(new_buffer) >= flush_threshold(state.opts) do
        if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
        flushed = flush_buffer(new_state)
        %{flushed | timer_ref: schedule_flush(state.opts)}
      else
        new_state
      end
    end
  end

  defp flush_buffer(%{buffer: []} = state), do: state

  defp flush_buffer(state) do
    events_by_workspace = Enum.group_by(state.buffer, & &1.workspace_id)

    Enum.each(events_by_workspace, fn {workspace_id, events} ->
      inputs =
        Enum.map(events, fn e ->
          %{
            event_type: e.event_type,
            message: e.message,
            metadata: e.metadata,
            agent_run_id: e.run_id,
            dedup_key: e.dedup_key
          }
        end)

      Ash.bulk_create(inputs, Citadel.Tasks.AgentRunEvent, :create_sink_event,
        tenant: workspace_id,
        authorize?: false,
        return_errors?: false,
        stop_on_error?: false
      )
    end)

    %{state | buffer: [], seen_dedup_keys: MapSet.new()}
  rescue
    err ->
      Logger.error("EventSink: failed to flush buffer: #{inspect(err)}")
      %{state | buffer: [], seen_dedup_keys: MapSet.new()}
  end

  defp significant_stream_event?(event_data) when is_map(event_data) do
    event_type(event_data) in ["tool_use", "tool_result", "error", "message_stop"]
  end

  defp significant_stream_event?(_), do: false

  defp stream_message(event_data) when is_map(event_data) do
    build_stream_message(event_type(event_data), event_data)
  end

  defp stream_message(_), do: "Stream event"

  defp build_stream_message("tool_use", event_data) do
    "Tool call: #{Map.get(event_data, "name", Map.get(event_data, :name, "unknown"))}"
  end

  defp build_stream_message("tool_result", _event_data), do: "Tool result received"

  defp build_stream_message("error", event_data) do
    "Stream error: #{Map.get(event_data, "message", Map.get(event_data, :message, "unknown error"))}"
  end

  defp build_stream_message(type, _event_data), do: "Stream event: #{type}"

  defp event_type(event_data) do
    Map.get(event_data, "type", Map.get(event_data, :type))
  end

  defp schedule_flush(opts) do
    interval = config(opts, :flush_interval, @flush_interval)
    Process.send_after(self(), :flush, interval)
  end

  defp flush_threshold(opts) do
    config(opts, :flush_threshold, @flush_threshold)
  end

  defp config(opts, key, default) do
    app_config = Application.get_env(:citadel, __MODULE__, [])
    Keyword.get(opts, key, Keyword.get(app_config, key, default))
  end
end
