defmodule CitadelWeb.AgentChannelTest do
  use CitadelWeb.ChannelCase, async: true

  alias CitadelWeb.AgentChannel

  setup do
    workspace_id = Ash.UUID.generate()
    agent_name = "test-agent-#{System.unique_integer([:positive])}"

    {:ok, _, socket} =
      CitadelWeb.AgentSocket
      |> socket("agent_socket:#{workspace_id}", %{workspace_id: workspace_id})
      |> subscribe_and_join(AgentChannel, "agents:#{workspace_id}", %{
        "agent_name" => agent_name
      })

    %{socket: socket, workspace_id: workspace_id, agent_name: agent_name}
  end

  describe "join" do
    test "defaults to idle status when no status provided", %{agent_name: agent_name} do
      workspace_id = Ash.UUID.generate()

      {:ok, _reply, socket} =
        CitadelWeb.AgentSocket
        |> socket("agent_socket:#{workspace_id}", %{workspace_id: workspace_id})
        |> subscribe_and_join(AgentChannel, "agents:#{workspace_id}", %{
          "agent_name" => agent_name
        })

      assert socket.assigns.initial_status == "idle"
      assert socket.assigns.initial_task_id == nil
    end

    test "uses status from join payload when provided" do
      workspace_id = Ash.UUID.generate()
      agent_name = "test-agent-#{System.unique_integer([:positive])}"
      task_id = Ash.UUID.generate()

      {:ok, _reply, socket} =
        CitadelWeb.AgentSocket
        |> socket("agent_socket:#{workspace_id}", %{workspace_id: workspace_id})
        |> subscribe_and_join(AgentChannel, "agents:#{workspace_id}", %{
          "agent_name" => agent_name,
          "status" => "working",
          "current_task_id" => task_id
        })

      assert socket.assigns.initial_status == "working"
      assert socket.assigns.initial_task_id == task_id
    end
  end

  describe "stream_output" do
    test "broadcasts event data to the run's PubSub topic", %{socket: socket} do
      run_id = Ash.UUID.generate()
      topic = "agent_run_output:#{run_id}"
      CitadelWeb.Endpoint.subscribe(topic)

      event_data = %{"type" => "assistant", "content" => "Hello"}
      push(socket, "stream_output", %{"run_id" => run_id, "event" => event_data})

      assert_receive %Phoenix.Socket.Broadcast{
        topic: ^topic,
        event: "stream_event",
        payload: %{event: ^event_data}
      }
    end

    test "handles missing run_id gracefully", %{socket: socket} do
      import ExUnit.CaptureLog

      capture_log(fn ->
        push(socket, "stream_output", %{"event" => %{"type" => "text"}})
        Process.sleep(50)
      end)

      assert Process.alive?(socket.channel_pid)
    end
  end

  describe "stream_complete" do
    test "broadcasts completion signal to the run's PubSub topic", %{socket: socket} do
      run_id = Ash.UUID.generate()
      topic = "agent_run_output:#{run_id}"
      CitadelWeb.Endpoint.subscribe(topic)

      push(socket, "stream_complete", %{"run_id" => run_id})

      assert_receive %Phoenix.Socket.Broadcast{
        topic: ^topic,
        event: "stream_complete",
        payload: %{}
      }
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
