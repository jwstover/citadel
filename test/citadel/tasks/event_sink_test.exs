defmodule Citadel.Tasks.EventSinkTest do
  use Citadel.DataCase, async: false

  alias Citadel.Tasks
  alias Citadel.Tasks.EventSink
  alias Ecto.Adapters.SQL.Sandbox

  @fast_flush [flush_interval: 50, flush_threshold: 100]

  setup do
    user = generate(user())
    workspace = generate(workspace([], actor: user))

    task_state =
      Tasks.create_task_state!(%{
        name: "Task State #{System.unique_integer([:positive])}",
        order: 1
      })

    task =
      Tasks.create_task!(
        %{
          title: "Test Task #{System.unique_integer([:positive])}",
          task_state_id: task_state.id,
          workspace_id: workspace.id
        },
        actor: user,
        tenant: workspace.id
      )

    {:ok, pid} =
      start_supervised(
        {EventSink, @fast_flush ++ [name: :"event_sink_#{System.unique_integer([:positive])}"]},
        id: :test_event_sink
      )

    Sandbox.allow(Citadel.Repo, self(), pid)

    {:ok, user: user, workspace: workspace, task: task, sink: pid}
  end

  defp create_running_run(task, user, workspace) do
    run =
      Tasks.create_agent_run!(
        %{task_id: task.id},
        actor: user,
        tenant: workspace.id
      )

    Tasks.update_agent_run!(
      run,
      %{status: :running, started_at: DateTime.utc_now()},
      actor: user,
      tenant: workspace.id
    )
  end

  defp notify_sink_of_run(sink, run) do
    send(sink, %Phoenix.Socket.Broadcast{
      topic: "tasks:agent_activity",
      event: "run_started",
      payload: %{run_id: run.id, task_id: run.task_id, workspace_id: run.workspace_id}
    })

    :sys.get_state(sink)
  end

  defp flush_sink(sink) do
    send(sink, :flush)
    :sys.get_state(sink)
  end

  defp list_events(run_id, workspace_id) do
    Tasks.list_agent_run_events!(run_id, authorize?: false, tenant: workspace_id)
  end

  describe "event subscription via tasks:agent_activity" do
    test "subscribes to run-specific topics when notified of a new run", %{
      task: task,
      user: user,
      workspace: workspace,
      sink: sink
    } do
      run = create_running_run(task, user, workspace)

      send(sink, %Phoenix.Socket.Broadcast{
        topic: "tasks:agent_activity",
        event: "run_started",
        payload: %{run_id: run.id, task_id: run.task_id, workspace_id: run.workspace_id}
      })

      state = :sys.get_state(sink)

      assert MapSet.member?(state.subscribed_topics, "agent_run_output:#{run.id}")
      assert MapSet.member?(state.subscribed_topics, "tasks:agent_runs:#{run.task_id}")
      assert MapSet.member?(state.subscribed_topics, "tasks:refinement:#{run.id}")
    end

    test "duplicate subscriptions are not created for same topics", %{
      task: task,
      user: user,
      workspace: workspace,
      sink: sink
    } do
      run = create_running_run(task, user, workspace)
      notify_sink_of_run(sink, run)
      notify_sink_of_run(sink, run)

      state = :sys.get_state(sink)
      topics = MapSet.to_list(state.subscribed_topics)
      output_topics = Enum.filter(topics, &String.starts_with?(&1, "agent_run_output:#{run.id}"))
      assert length(output_topics) == 1
    end
  end

  describe "stream output events" do
    test "significant stream events are buffered and persisted", %{
      task: task,
      user: user,
      workspace: workspace,
      sink: sink
    } do
      run = create_running_run(task, user, workspace)
      notify_sink_of_run(sink, run)

      send(sink, %Phoenix.Socket.Broadcast{
        topic: "agent_run_output:#{run.id}",
        event: "stream_event",
        payload: %{event: %{"type" => "tool_use", "name" => "bash"}}
      })

      flush_sink(sink)

      events = list_events(run.id, workspace.id)
      assert length(events) == 1
      [event] = events
      assert event.event_type == :stream_output
      assert event.message == "Tool call: bash"
    end

    test "stream_complete events are persisted", %{
      task: task,
      user: user,
      workspace: workspace,
      sink: sink
    } do
      run = create_running_run(task, user, workspace)
      notify_sink_of_run(sink, run)

      send(sink, %Phoenix.Socket.Broadcast{
        topic: "agent_run_output:#{run.id}",
        event: "stream_complete",
        payload: %{}
      })

      flush_sink(sink)

      events = list_events(run.id, workspace.id)
      assert length(events) == 1
      assert hd(events).event_type == :stream_output
      assert hd(events).message == "Stream completed"
    end

    test "non-significant stream events are filtered out", %{
      task: task,
      user: user,
      workspace: workspace,
      sink: sink
    } do
      run = create_running_run(task, user, workspace)
      notify_sink_of_run(sink, run)

      for _i <- 1..5 do
        send(sink, %Phoenix.Socket.Broadcast{
          topic: "agent_run_output:#{run.id}",
          event: "stream_event",
          payload: %{event: %{"type" => "content_block_delta", "delta" => %{"text" => "hi"}}}
        })
      end

      flush_sink(sink)

      events = list_events(run.id, workspace.id)
      assert events == []
    end
  end

  describe "status change events" do
    test "run status changes are persisted", %{
      task: task,
      user: user,
      workspace: workspace,
      sink: sink
    } do
      run = create_running_run(task, user, workspace)
      notify_sink_of_run(sink, run)

      send(sink, %Phoenix.Socket.Broadcast{
        topic: "tasks:agent_runs:#{run.task_id}",
        event: "update",
        payload: %{data: %{id: run.id, status: :completed}}
      })

      flush_sink(sink)

      events = list_events(run.id, workspace.id)
      assert length(events) == 1
      [event] = events
      assert event.event_type == :status_change
      assert event.metadata == %{"status" => "completed"}
    end

    test "cancel action status changes are persisted", %{
      task: task,
      user: user,
      workspace: workspace,
      sink: sink
    } do
      run = create_running_run(task, user, workspace)
      notify_sink_of_run(sink, run)

      send(sink, %Phoenix.Socket.Broadcast{
        topic: "tasks:agent_runs:#{run.task_id}",
        event: "cancel",
        payload: %{data: %{id: run.id, status: :cancelled}}
      })

      flush_sink(sink)

      events = list_events(run.id, workspace.id)
      assert length(events) == 1
      assert hd(events).event_type == :status_change
    end
  end

  describe "stall detected events" do
    test "stall status changes are persisted as stall_detected", %{
      task: task,
      user: user,
      workspace: workspace,
      sink: sink
    } do
      run = create_running_run(task, user, workspace)
      notify_sink_of_run(sink, run)

      send(sink, %Phoenix.Socket.Broadcast{
        topic: "tasks:agent_runs:#{run.task_id}",
        event: "update_stall_status",
        payload: %{data: %{id: run.id, stall_status: :stalled}}
      })

      flush_sink(sink)

      events = list_events(run.id, workspace.id)
      assert length(events) == 1
      [event] = events
      assert event.event_type == :stall_detected
      assert event.metadata == %{"stall_status" => "stalled"}
    end
  end

  describe "refinement events" do
    test "refinement cycle creation is persisted as refinement_started", %{
      task: task,
      user: user,
      workspace: workspace,
      sink: sink
    } do
      run = create_running_run(task, user, workspace)
      notify_sink_of_run(sink, run)

      fake_cycle = %{id: Ash.UUID.generate(), max_iterations: 3}

      send(sink, %Phoenix.Socket.Broadcast{
        topic: "tasks:refinement:#{run.id}",
        event: "create",
        payload: %{data: fake_cycle}
      })

      flush_sink(sink)

      events = list_events(run.id, workspace.id)
      assert length(events) == 1
      [event] = events
      assert event.event_type == :refinement_started
      assert event.metadata["max_iterations"] == 3
    end

    test "refinement cycle completion is persisted as refinement_completed", %{
      task: task,
      user: user,
      workspace: workspace,
      sink: sink
    } do
      run = create_running_run(task, user, workspace)
      notify_sink_of_run(sink, run)

      fake_cycle = %{id: Ash.UUID.generate(), status: :passed, final_score: 0.9}

      send(sink, %Phoenix.Socket.Broadcast{
        topic: "tasks:refinement:#{run.id}",
        event: "complete",
        payload: %{data: fake_cycle}
      })

      flush_sink(sink)

      events = list_events(run.id, workspace.id)
      assert length(events) == 1
      [event] = events
      assert event.event_type == :refinement_completed
      assert event.metadata["status"] == "passed"
      assert event.metadata["final_score"] == 0.9
    end
  end

  describe "batching" do
    test "events buffer and flush after interval", %{
      task: task,
      user: user,
      workspace: workspace,
      sink: sink
    } do
      run = create_running_run(task, user, workspace)
      notify_sink_of_run(sink, run)

      for i <- 1..3 do
        send(sink, %Phoenix.Socket.Broadcast{
          topic: "agent_run_output:#{run.id}",
          event: "stream_event",
          payload: %{event: %{"type" => "tool_use", "name" => "tool_#{i}"}}
        })
      end

      state = :sys.get_state(sink)
      assert length(state.buffer) == 3

      events_before = list_events(run.id, workspace.id)
      assert events_before == []

      flush_sink(sink)

      events_after = list_events(run.id, workspace.id)
      assert length(events_after) == 3
    end

    test "buffer flushes automatically at threshold", %{
      task: task,
      user: user,
      workspace: workspace
    } do
      {:ok, pid} =
        start_supervised(
          {EventSink,
           flush_interval: :timer.seconds(3600),
           flush_threshold: 3,
           name: :"event_sink_threshold_#{System.unique_integer([:positive])}"},
          id: :test_event_sink_threshold
        )

      Sandbox.allow(Citadel.Repo, self(), pid)

      run = create_running_run(task, user, workspace)

      send(pid, %Phoenix.Socket.Broadcast{
        topic: "tasks:agent_activity",
        event: "run_started",
        payload: %{run_id: run.id, task_id: run.task_id, workspace_id: run.workspace_id}
      })

      :sys.get_state(pid)

      for i <- 1..3 do
        send(pid, %Phoenix.Socket.Broadcast{
          topic: "agent_run_output:#{run.id}",
          event: "stream_event",
          payload: %{event: %{"type" => "tool_use", "name" => "tool_#{i}"}}
        })
      end

      :sys.get_state(pid)

      events = list_events(run.id, workspace.id)
      assert length(events) == 3
    end
  end

  describe "deduplication" do
    test "same event received twice is only persisted once", %{
      task: task,
      user: user,
      workspace: workspace,
      sink: sink
    } do
      run = create_running_run(task, user, workspace)
      notify_sink_of_run(sink, run)

      broadcast = %Phoenix.Socket.Broadcast{
        topic: "agent_run_output:#{run.id}",
        event: "stream_event",
        payload: %{event: %{"type" => "tool_use", "name" => "bash"}}
      }

      send(sink, broadcast)
      send(sink, broadcast)

      flush_sink(sink)

      events = list_events(run.id, workspace.id)
      assert length(events) == 1
    end
  end
end
