defmodule CitadelWeb.Api.AgentControllerTest do
  use CitadelWeb.ConnCase, async: true

  alias Citadel.Accounts.ApiKey
  alias Citadel.Tasks

  setup do
    user = generate(user())
    organization = generate(organization([], actor: user))
    workspace = generate(workspace([organization_id: organization.id], actor: user))

    task_state =
      Tasks.create_task_state!(%{
        name: "Todo #{System.unique_integer([:positive])}",
        order: 1
      })

    expires_at = DateTime.add(DateTime.utc_now(), 30, :day)

    {:ok, api_key} =
      ApiKey
      |> Ash.Changeset.for_create(:create, %{
        name: "Test Agent Key",
        user_id: user.id,
        workspace_id: workspace.id,
        expires_at: expires_at
      })
      |> Ash.create(authorize?: false)

    raw_key = api_key.__metadata__[:plaintext_api_key]

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{raw_key}")
      |> put_req_header("accept", "application/json")

    %{conn: conn, user: user, workspace: workspace, task_state: task_state}
  end

  defp create_task(workspace, user, task_state, attrs \\ []) do
    defaults = [workspace_id: workspace.id, task_state_id: task_state.id, agent_eligible: true]
    generate(task(Keyword.merge(defaults, attrs), actor: user, tenant: workspace.id))
  end

  describe "GET /api/agent/tasks/next" do
    test "returns the next eligible task", ctx do
      task = create_task(ctx.workspace, ctx.user, ctx.task_state)

      conn = get(ctx.conn, ~p"/api/agent/tasks/next")

      assert %{"data" => data} = json_response(conn, 200)
      assert data["id"] == task.id
      assert data["title"] == task.title
      assert data["agent_eligible"] == true
      assert data["task_state"]["name"] != nil
    end

    test "returns 204 when no tasks available", ctx do
      conn = get(ctx.conn, ~p"/api/agent/tasks/next")

      assert response(conn, 204)
    end

    test "skips tasks that are not agent_eligible", ctx do
      _non_eligible = create_task(ctx.workspace, ctx.user, ctx.task_state, agent_eligible: false)

      conn = get(ctx.conn, ~p"/api/agent/tasks/next")

      assert response(conn, 204)
    end

    test "skips tasks with pending agent runs", ctx do
      task = create_task(ctx.workspace, ctx.user, ctx.task_state)

      generate(
        agent_run(
          [task_id: task.id, status: :pending],
          actor: ctx.user,
          tenant: ctx.workspace.id
        )
      )

      conn = get(ctx.conn, ~p"/api/agent/tasks/next")

      assert response(conn, 204)
    end

    test "skips tasks with running agent runs", ctx do
      task = create_task(ctx.workspace, ctx.user, ctx.task_state)

      generate(
        agent_run(
          [task_id: task.id, status: :running],
          actor: ctx.user,
          tenant: ctx.workspace.id
        )
      )

      conn = get(ctx.conn, ~p"/api/agent/tasks/next")

      assert response(conn, 204)
    end

    test "returns tasks with completed agent runs", ctx do
      task = create_task(ctx.workspace, ctx.user, ctx.task_state)

      run =
        generate(
          agent_run(
            [task_id: task.id],
            actor: ctx.user,
            tenant: ctx.workspace.id
          )
        )

      Tasks.update_agent_run!(run, %{status: :completed},
        actor: ctx.user,
        tenant: ctx.workspace.id
      )

      conn = get(ctx.conn, ~p"/api/agent/tasks/next")

      assert %{"data" => data} = json_response(conn, 200)
      assert data["id"] == task.id
    end

    test "returns tasks with failed agent runs", ctx do
      task = create_task(ctx.workspace, ctx.user, ctx.task_state)

      run =
        generate(
          agent_run(
            [task_id: task.id],
            actor: ctx.user,
            tenant: ctx.workspace.id
          )
        )

      Tasks.update_agent_run!(run, %{status: :failed}, actor: ctx.user, tenant: ctx.workspace.id)

      conn = get(ctx.conn, ~p"/api/agent/tasks/next")

      assert %{"data" => data} = json_response(conn, 200)
      assert data["id"] == task.id
    end

    test "returns 401 without authentication" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/agent/tasks/next")

      assert json_response(conn, 401)
    end
  end

  describe "POST /api/agent/tasks/:task_id/runs" do
    test "creates an agent run", ctx do
      task = create_task(ctx.workspace, ctx.user, ctx.task_state)

      conn = post(ctx.conn, ~p"/api/agent/tasks/#{task.id}/runs", %{})

      assert %{"data" => data} = json_response(conn, 201)
      assert data["task_id"] == task.id
      assert data["status"] == "pending"
    end

    test "creates an agent run with custom status", ctx do
      task = create_task(ctx.workspace, ctx.user, ctx.task_state)

      conn = post(ctx.conn, ~p"/api/agent/tasks/#{task.id}/runs", %{"status" => "running"})

      assert %{"data" => data} = json_response(conn, 201)
      assert data["status"] == "running"
    end
  end

  describe "PATCH /api/agent/tasks/:id" do
    test "updates a task's state", ctx do
      task = create_task(ctx.workspace, ctx.user, ctx.task_state)

      new_state =
        Tasks.create_task_state!(%{
          name: "In Review #{System.unique_integer([:positive])}",
          order: 4
        })

      conn =
        patch(ctx.conn, ~p"/api/agent/tasks/#{task.id}", %{
          "task_state_id" => new_state.id
        })

      assert %{"data" => data} = json_response(conn, 200)
      assert data["id"] == task.id
      assert data["task_state"]["id"] == new_state.id
      assert data["task_state"]["name"] == new_state.name
    end

    test "returns 404 for non-existent task", ctx do
      fake_id = Ash.UUID.generate()

      conn =
        patch(ctx.conn, ~p"/api/agent/tasks/#{fake_id}", %{
          "task_state_id" => ctx.task_state.id
        })

      assert json_response(conn, 404)
    end

    test "returns 422 for invalid task_state_id", ctx do
      task = create_task(ctx.workspace, ctx.user, ctx.task_state)
      fake_state_id = Ash.UUID.generate()

      conn =
        patch(ctx.conn, ~p"/api/agent/tasks/#{task.id}", %{
          "task_state_id" => fake_state_id
        })

      assert json_response(conn, 422)
    end
  end

  describe "GET /api/agent/task-states" do
    test "returns all task states", ctx do
      conn = get(ctx.conn, ~p"/api/agent/task-states")

      assert %{"data" => states} = json_response(conn, 200)
      assert is_list(states)
      assert length(states) >= 1

      state = List.first(states)
      assert Map.has_key?(state, "id")
      assert Map.has_key?(state, "name")
      assert Map.has_key?(state, "order")
      assert Map.has_key?(state, "is_complete")
    end

    test "returns states sorted by order", ctx do
      conn = get(ctx.conn, ~p"/api/agent/task-states")

      assert %{"data" => states} = json_response(conn, 200)
      orders = Enum.map(states, & &1["order"])
      assert orders == Enum.sort(orders)
    end

    test "returns 401 without authentication" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/agent/task-states")

      assert json_response(conn, 401)
    end
  end

  describe "POST /api/agent/runs/:id/events" do
    test "creates an agent run event", ctx do
      task = create_task(ctx.workspace, ctx.user, ctx.task_state)

      run =
        generate(
          agent_run(
            [task_id: task.id],
            actor: ctx.user,
            tenant: ctx.workspace.id
          )
        )

      conn =
        post(ctx.conn, ~p"/api/agent/runs/#{run.id}/events", %{
          "event_type" => "run_started",
          "message" => "Agent starting work"
        })

      assert %{"data" => data} = json_response(conn, 201)
      assert data["agent_run_id"] == run.id
      assert data["event_type"] == "run_started"
      assert data["message"] == "Agent starting work"
    end

    test "creates an event with metadata", ctx do
      task = create_task(ctx.workspace, ctx.user, ctx.task_state)

      run =
        generate(
          agent_run(
            [task_id: task.id],
            actor: ctx.user,
            tenant: ctx.workspace.id
          )
        )

      conn =
        post(ctx.conn, ~p"/api/agent/runs/#{run.id}/events", %{
          "event_type" => "run_failed",
          "message" => "Compilation failed",
          "metadata" => %{"exit_code" => 1, "file" => "lib/foo.ex"}
        })

      assert %{"data" => data} = json_response(conn, 201)
      assert data["event_type"] == "run_failed"
      assert data["metadata"]["exit_code"] == 1
      assert data["metadata"]["file"] == "lib/foo.ex"
    end

    test "returns 422 for invalid event_type", ctx do
      task = create_task(ctx.workspace, ctx.user, ctx.task_state)

      run =
        generate(
          agent_run(
            [task_id: task.id],
            actor: ctx.user,
            tenant: ctx.workspace.id
          )
        )

      conn =
        post(ctx.conn, ~p"/api/agent/runs/#{run.id}/events", %{
          "event_type" => "invalid_type"
        })

      assert json_response(conn, 422)
    end
  end

  describe "PATCH /api/agent/runs/:id" do
    test "updates an agent run status", ctx do
      task = create_task(ctx.workspace, ctx.user, ctx.task_state)

      run =
        generate(
          agent_run(
            [task_id: task.id],
            actor: ctx.user,
            tenant: ctx.workspace.id
          )
        )

      conn =
        patch(ctx.conn, ~p"/api/agent/runs/#{run.id}", %{
          "status" => "completed",
          "diff" => "--- a/file.ex\n+++ b/file.ex",
          "test_output" => "All tests passed"
        })

      assert %{"data" => data} = json_response(conn, 200)
      assert data["status"] == "completed"
      assert data["diff"] == "--- a/file.ex\n+++ b/file.ex"
      assert data["test_output"] == "All tests passed"
    end

    test "updates with error details on failure", ctx do
      task = create_task(ctx.workspace, ctx.user, ctx.task_state)

      run =
        generate(
          agent_run(
            [task_id: task.id],
            actor: ctx.user,
            tenant: ctx.workspace.id
          )
        )

      conn =
        patch(ctx.conn, ~p"/api/agent/runs/#{run.id}", %{
          "status" => "failed",
          "error_message" => "Compilation error",
          "logs" => "** (CompileError) lib/foo.ex:1"
        })

      assert %{"data" => data} = json_response(conn, 200)
      assert data["status"] == "failed"
      assert data["error_message"] == "Compilation error"
      assert data["logs"] == "** (CompileError) lib/foo.ex:1"
    end

    test "returns 404 for non-existent run", ctx do
      fake_id = Ash.UUID.generate()

      conn = patch(ctx.conn, ~p"/api/agent/runs/#{fake_id}", %{"status" => "completed"})

      assert json_response(conn, 404)
    end
  end
end
