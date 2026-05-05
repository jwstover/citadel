defmodule CitadelWeb.AgentChannelTest do
  use CitadelWeb.ChannelCase, async: true

  alias Citadel.Tasks
  alias CitadelWeb.AgentChannel

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
          task_state_id: task_state.id
        },
        actor: user,
        tenant: workspace.id
      )

    agent_name = "test-agent-#{System.unique_integer([:positive])}"

    {:ok, _, socket} =
      CitadelWeb.AgentSocket
      |> socket("agent_socket:#{workspace.id}", %{
        current_user: user,
        workspace_id: workspace.id
      })
      |> subscribe_and_join(AgentChannel, "agents:#{workspace.id}", %{
        "agent_name" => agent_name
      })

    %{
      socket: socket,
      workspace: workspace,
      user: user,
      task: task,
      agent_name: agent_name
    }
  end

  describe "join" do
    test "defaults to idle status when no status provided", %{
      agent_name: agent_name,
      user: user,
      workspace: workspace
    } do
      {:ok, _reply, socket} =
        CitadelWeb.AgentSocket
        |> socket("agent_socket:#{workspace.id}", %{
          current_user: user,
          workspace_id: workspace.id
        })
        |> subscribe_and_join(AgentChannel, "agents:#{workspace.id}", %{
          "agent_name" => agent_name
        })

      assert socket.assigns.status == "idle"
      assert socket.assigns.current_task_id == nil
    end

    test "uses status from join payload when provided", %{user: user, workspace: workspace} do
      agent_name = "test-agent-#{System.unique_integer([:positive])}"
      task_id = Ash.UUID.generate()

      {:ok, _reply, socket} =
        CitadelWeb.AgentSocket
        |> socket("agent_socket:#{workspace.id}", %{
          current_user: user,
          workspace_id: workspace.id
        })
        |> subscribe_and_join(AgentChannel, "agents:#{workspace.id}", %{
          "agent_name" => agent_name,
          "status" => "working",
          "current_task_id" => task_id
        })

      assert socket.assigns.status == "working"
      assert socket.assigns.current_task_id == task_id
    end
  end

  describe "stream_output" do
    test "persists a stream event for the run", ctx do
      run =
        generate(
          agent_run(
            [task_id: ctx.task.id],
            actor: ctx.user,
            tenant: ctx.workspace.id
          )
        )

      event_data = %{"type" => "assistant", "content" => "Hello"}

      push(ctx.socket, "stream_output", %{"run_id" => run.id, "event" => event_data})
      Process.sleep(50)

      events =
        Tasks.list_agent_run_stream_events!(run.id,
          actor: ctx.user,
          tenant: ctx.workspace.id
        )

      assert [event] = events
      assert event.event_type == :stream
      assert event.metadata == event_data
    end

    test "broadcasts to the agent_run_events PubSub topic", ctx do
      run =
        generate(
          agent_run(
            [task_id: ctx.task.id],
            actor: ctx.user,
            tenant: ctx.workspace.id
          )
        )

      topic = "tasks:agent_run_events:#{run.id}"
      CitadelWeb.Endpoint.subscribe(topic)

      event_data = %{"type" => "assistant", "content" => "Hello"}
      push(ctx.socket, "stream_output", %{"run_id" => run.id, "event" => event_data})

      assert_receive %Phoenix.Socket.Broadcast{
        topic: ^topic,
        event: "create",
        payload: %{data: %{event_type: :stream, metadata: ^event_data}}
      }
    end

    test "decodes JSON string events into structured metadata", ctx do
      run =
        generate(
          agent_run(
            [task_id: ctx.task.id],
            actor: ctx.user,
            tenant: ctx.workspace.id
          )
        )

      json_line = ~s({"type":"assistant","content":"Hi"})

      push(ctx.socket, "stream_output", %{"run_id" => run.id, "event" => json_line})
      Process.sleep(50)

      [event] =
        Tasks.list_agent_run_stream_events!(run.id,
          actor: ctx.user,
          tenant: ctx.workspace.id
        )

      assert event.metadata == %{"type" => "assistant", "content" => "Hi"}
    end

    test "handles missing run_id gracefully", %{socket: socket} do
      import ExUnit.CaptureLog

      capture_log(fn ->
        push(socket, "stream_output", %{"event" => %{"type" => "text"}})
        Process.sleep(50)
      end)

      assert Process.alive?(socket.channel_pid)
    end

    test "logs and stays alive when the run does not exist", %{socket: socket} do
      import ExUnit.CaptureLog

      log =
        capture_log(fn ->
          push(socket, "stream_output", %{
            "run_id" => Ash.UUID.generate(),
            "event" => %{"type" => "text"}
          })

          Process.sleep(50)
        end)

      assert log =~ "AgentChannel failed to persist stream event"
      assert Process.alive?(socket.channel_pid)
    end
  end

  describe "stream_complete" do
    test "is a no-op and keeps the channel alive", %{socket: socket} do
      push(socket, "stream_complete", %{"run_id" => Ash.UUID.generate()})
      Process.sleep(50)

      assert Process.alive?(socket.channel_pid)
    end

    test "handles missing run_id gracefully", %{socket: socket} do
      import ExUnit.CaptureLog

      capture_log(fn ->
        push(socket, "stream_complete", %{})
        Process.sleep(50)
      end)

      assert Process.alive?(socket.channel_pid)
    end
  end

  describe "unrecognized events" do
    @tag capture_log: true
    test "does not crash the channel", %{socket: socket} do
      push(socket, "unknown_event", %{"foo" => "bar"})
      Process.sleep(50)

      assert Process.alive?(socket.channel_pid)
    end
  end
end
