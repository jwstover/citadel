defmodule Citadel.Tasks.StallDetectorTest do
  use Citadel.DataCase, async: false

  alias Citadel.Tasks
  alias Citadel.Tasks.StallDetector
  alias Ecto.Adapters.SQL.Sandbox

  @short_thresholds [
    check_interval: :timer.seconds(3600),
    suspect_threshold: 5,
    stall_threshold: 10,
    timeout_threshold: 20,
    db_debounce_interval: 0
  ]

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
        {StallDetector,
         @short_thresholds ++ [name: :"stall_detector_#{System.unique_integer([:positive])}"]},
        id: :test_stall_detector
      )

    Sandbox.allow(Citadel.Repo, self(), pid)

    {:ok, user: user, workspace: workspace, task: task, detector: pid}
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

  describe "record_activity/1" do
    test "tracks a newly running agent run", %{
      task: task,
      user: user,
      workspace: workspace,
      detector: detector
    } do
      run = create_running_run(task, user, workspace)

      StallDetector.record_activity(detector, run.id)

      # Allow handle_cast to process
      :sys.get_state(detector)

      tracker = StallDetector.get_tracker(detector)
      assert Map.has_key?(tracker, run.id)
      assert tracker[run.id].task_id == task.id
      assert tracker[run.id].workspace_id == workspace.id
      assert tracker[run.id].stall_status == nil
    end

    test "updates last_activity_at for an already-tracked run", %{
      task: task,
      user: user,
      workspace: workspace,
      detector: detector
    } do
      run = create_running_run(task, user, workspace)

      StallDetector.record_activity(detector, run.id)
      :sys.get_state(detector)
      first_time = StallDetector.get_tracker(detector)[run.id].last_activity_at

      Process.sleep(10)

      StallDetector.record_activity(detector, run.id)
      :sys.get_state(detector)
      second_time = StallDetector.get_tracker(detector)[run.id].last_activity_at

      assert DateTime.compare(second_time, first_time) == :gt
    end

    test "writes last_activity_at to the database (debounced)", %{
      task: task,
      user: user,
      workspace: workspace,
      detector: detector
    } do
      run = create_running_run(task, user, workspace)

      StallDetector.record_activity(detector, run.id)

      # Force all pending messages to be processed
      :sys.get_state(detector)

      updated = Tasks.get_agent_run!(run.id, authorize?: false, tenant: workspace.id)
      assert updated.last_activity_at != nil
    end
  end

  describe "stall detection periodic check" do
    test "transitions run to :suspect when silent past suspect threshold", %{
      task: task,
      user: user,
      workspace: workspace,
      detector: detector
    } do
      run = create_running_run(task, user, workspace)

      old_time = DateTime.add(DateTime.utc_now(), -7, :second)

      :sys.replace_state(detector, fn state ->
        put_in(state, [:tracker, run.id], %{
          last_activity_at: old_time,
          task_id: task.id,
          workspace_id: workspace.id,
          stall_status: nil
        })
      end)

      send(detector, :check_stalls)
      :sys.get_state(detector)

      # Wait for the async apply_stall_status handle_info
      :sys.get_state(detector)

      tracker = StallDetector.get_tracker(detector)
      assert tracker[run.id].stall_status == :suspect
    end

    test "transitions run to :stalled when silent past stall threshold", %{
      task: task,
      user: user,
      workspace: workspace,
      detector: detector
    } do
      run = create_running_run(task, user, workspace)

      old_time = DateTime.add(DateTime.utc_now(), -15, :second)

      :sys.replace_state(detector, fn state ->
        put_in(state, [:tracker, run.id], %{
          last_activity_at: old_time,
          task_id: task.id,
          workspace_id: workspace.id,
          stall_status: nil
        })
      end)

      send(detector, :check_stalls)
      :sys.get_state(detector)
      :sys.get_state(detector)

      tracker = StallDetector.get_tracker(detector)
      assert tracker[run.id].stall_status == :stalled
    end

    test "broadcasts stall_status change via PubSub when run becomes suspect", %{
      task: task,
      user: user,
      workspace: workspace,
      detector: detector
    } do
      run = create_running_run(task, user, workspace)
      CitadelWeb.Endpoint.subscribe("tasks:agent_runs:#{task.id}")

      old_time = DateTime.add(DateTime.utc_now(), -7, :second)

      :sys.replace_state(detector, fn state ->
        put_in(state, [:tracker, run.id], %{
          last_activity_at: old_time,
          task_id: task.id,
          workspace_id: workspace.id,
          stall_status: nil
        })
      end)

      send(detector, :check_stalls)
      :sys.get_state(detector)
      :sys.get_state(detector)

      assert_receive %Phoenix.Socket.Broadcast{
        topic: "tasks:agent_runs:" <> _,
        event: "update_stall_status"
      }
    end

    test "cancels run and removes from tracker when timed out", %{
      task: task,
      user: user,
      workspace: workspace,
      detector: detector
    } do
      run = create_running_run(task, user, workspace)

      old_time = DateTime.add(DateTime.utc_now(), -25, :second)

      :sys.replace_state(detector, fn state ->
        put_in(state, [:tracker, run.id], %{
          last_activity_at: old_time,
          task_id: task.id,
          workspace_id: workspace.id,
          stall_status: :stalled
        })
      end)

      send(detector, :check_stalls)

      # Process check_stalls and the resulting apply_stall_status messages
      :sys.get_state(detector)
      :sys.get_state(detector)

      # Run should be removed from tracker
      tracker = StallDetector.get_tracker(detector)
      refute Map.has_key?(tracker, run.id)

      # Run should be cancelled in DB
      updated = Tasks.get_agent_run!(run.id, authorize?: false, tenant: workspace.id)
      assert updated.status == :cancelled
    end

    test "stall_status is updated in the database when transitioning", %{
      task: task,
      user: user,
      workspace: workspace,
      detector: detector
    } do
      run = create_running_run(task, user, workspace)

      old_time = DateTime.add(DateTime.utc_now(), -7, :second)

      :sys.replace_state(detector, fn state ->
        put_in(state, [:tracker, run.id], %{
          last_activity_at: old_time,
          task_id: task.id,
          workspace_id: workspace.id,
          stall_status: nil
        })
      end)

      send(detector, :check_stalls)
      :sys.get_state(detector)
      :sys.get_state(detector)

      updated = Tasks.get_agent_run!(run.id, authorize?: false, tenant: workspace.id)
      assert updated.stall_status == :suspect
    end

    test "does not re-transition if stall_status has not changed", %{
      task: task,
      user: user,
      workspace: workspace,
      detector: detector
    } do
      run = create_running_run(task, user, workspace)

      old_time = DateTime.add(DateTime.utc_now(), -7, :second)

      :sys.replace_state(detector, fn state ->
        put_in(state, [:tracker, run.id], %{
          last_activity_at: old_time,
          task_id: task.id,
          workspace_id: workspace.id,
          stall_status: :suspect
        })
      end)

      CitadelWeb.Endpoint.subscribe("tasks:agent_runs:#{task.id}")

      send(detector, :check_stalls)
      :sys.get_state(detector)
      :sys.get_state(detector)

      refute_receive %Phoenix.Socket.Broadcast{
                       event: "update_stall_status"
                     },
                     100
    end
  end

  describe "completed/failed/cancelled run removal" do
    test "removes run from tracker when cancel broadcast received", %{
      task: task,
      user: user,
      workspace: workspace,
      detector: detector
    } do
      run = create_running_run(task, user, workspace)

      StallDetector.record_activity(detector, run.id)
      :sys.get_state(detector)
      assert Map.has_key?(StallDetector.get_tracker(detector), run.id)

      Tasks.cancel_agent_run!(run, actor: user, tenant: workspace.id)

      # Give the GenServer time to process the PubSub message
      :sys.get_state(detector)

      tracker = StallDetector.get_tracker(detector)
      refute Map.has_key?(tracker, run.id)
    end

    test "removes run from tracker when completed update broadcast received", %{
      task: task,
      user: user,
      workspace: workspace,
      detector: detector
    } do
      run = create_running_run(task, user, workspace)

      StallDetector.record_activity(detector, run.id)
      :sys.get_state(detector)
      assert Map.has_key?(StallDetector.get_tracker(detector), run.id)

      Tasks.update_agent_run!(
        run,
        %{status: :completed, completed_at: DateTime.utc_now()},
        actor: user,
        tenant: workspace.id
      )

      :sys.get_state(detector)

      tracker = StallDetector.get_tracker(detector)
      refute Map.has_key?(tracker, run.id)
    end
  end

  describe "activity resets stall timer" do
    test "recording activity clears suspect status", %{
      task: task,
      user: user,
      workspace: workspace,
      detector: detector
    } do
      run = create_running_run(task, user, workspace)

      old_time = DateTime.add(DateTime.utc_now(), -7, :second)

      :sys.replace_state(detector, fn state ->
        put_in(state, [:tracker, run.id], %{
          last_activity_at: old_time,
          task_id: task.id,
          workspace_id: workspace.id,
          stall_status: :suspect
        })
      end)

      StallDetector.record_activity(detector, run.id)
      :sys.get_state(detector)

      tracker = StallDetector.get_tracker(detector)
      assert DateTime.compare(tracker[run.id].last_activity_at, old_time) == :gt

      send(detector, :check_stalls)
      :sys.get_state(detector)
      :sys.get_state(detector)

      updated_tracker = StallDetector.get_tracker(detector)
      assert updated_tracker[run.id].stall_status == nil
    end
  end
end
