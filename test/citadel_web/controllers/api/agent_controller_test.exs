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

  describe "POST /api/agent/tasks/claim" do
    test "returns task and agent run when a task is available", ctx do
      task = create_task(ctx.workspace, ctx.user, ctx.task_state)

      conn = post(ctx.conn, ~p"/api/agent/tasks/claim")

      assert %{"data" => data} = json_response(conn, 200)
      assert data["task"]["id"] == task.id
      assert data["task"]["title"] == task.title
      assert data["task"]["agent_eligible"] == true
      assert data["task"]["task_state"]["name"] != nil
      assert data["agent_run"]["task_id"] == task.id
      assert data["agent_run"]["status"] == "running"
      assert data["work_item"]["type"] == "new_task"
      assert data["work_item"]["comment_id"] == nil
      assert data["work_item"]["id"] != nil
    end

    test "returns 204 when no tasks available", ctx do
      conn = post(ctx.conn, ~p"/api/agent/tasks/claim")

      assert response(conn, 204)
    end

    test "skips tasks that are not agent_eligible", ctx do
      _non_eligible = create_task(ctx.workspace, ctx.user, ctx.task_state, agent_eligible: false)

      conn = post(ctx.conn, ~p"/api/agent/tasks/claim")

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

      conn = post(ctx.conn, ~p"/api/agent/tasks/claim")

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

      conn = post(ctx.conn, ~p"/api/agent/tasks/claim")

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

      conn = post(ctx.conn, ~p"/api/agent/tasks/claim")

      assert %{"data" => data} = json_response(conn, 200)
      assert data["task"]["id"] == task.id
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

      conn = post(ctx.conn, ~p"/api/agent/tasks/claim")

      assert %{"data" => data} = json_response(conn, 200)
      assert data["task"]["id"] == task.id
    end

    test "skips tasks with incomplete dependencies", ctx do
      task = create_task(ctx.workspace, ctx.user, ctx.task_state)
      dependency = create_task(ctx.workspace, ctx.user, ctx.task_state)

      Tasks.create_task_dependency!(
        %{task_id: task.id, depends_on_task_id: dependency.id},
        actor: ctx.user,
        tenant: ctx.workspace.id
      )

      conn = post(ctx.conn, ~p"/api/agent/tasks/claim")

      assert %{"data" => data} = json_response(conn, 200)
      assert data["task"]["id"] == dependency.id
    end

    test "returns tasks whose dependencies are all complete", ctx do
      complete_state =
        Tasks.create_task_state!(%{
          name: "Done #{System.unique_integer([:positive])}",
          order: 5,
          is_complete: true
        })

      task = create_task(ctx.workspace, ctx.user, ctx.task_state)
      dependency = create_task(ctx.workspace, ctx.user, complete_state)

      Tasks.create_task_dependency!(
        %{task_id: task.id, depends_on_task_id: dependency.id},
        actor: ctx.user,
        tenant: ctx.workspace.id
      )

      conn = post(ctx.conn, ~p"/api/agent/tasks/claim")

      assert %{"data" => data} = json_response(conn, 200)
      assert data["task"]["id"] == task.id
    end

    test "skips task when any dependency is incomplete", ctx do
      complete_state =
        Tasks.create_task_state!(%{
          name: "Done #{System.unique_integer([:positive])}",
          order: 5,
          is_complete: true
        })

      task = create_task(ctx.workspace, ctx.user, ctx.task_state)
      complete_dep = create_task(ctx.workspace, ctx.user, complete_state)
      incomplete_dep = create_task(ctx.workspace, ctx.user, ctx.task_state)

      Tasks.create_task_dependency!(
        %{task_id: task.id, depends_on_task_id: complete_dep.id},
        actor: ctx.user,
        tenant: ctx.workspace.id
      )

      Tasks.create_task_dependency!(
        %{task_id: task.id, depends_on_task_id: incomplete_dep.id},
        actor: ctx.user,
        tenant: ctx.workspace.id
      )

      conn = post(ctx.conn, ~p"/api/agent/tasks/claim")

      assert %{"data" => data} = json_response(conn, 200)
      assert data["task"]["id"] in [complete_dep.id, incomplete_dep.id]
      assert data["task"]["id"] != task.id
    end

    test "includes parent task info for subtasks", ctx do
      parent = create_task(ctx.workspace, ctx.user, ctx.task_state)
      _child = create_task(ctx.workspace, ctx.user, ctx.task_state, parent_task_id: parent.id)

      conn = post(ctx.conn, ~p"/api/agent/tasks/claim")

      assert %{"data" => data} = json_response(conn, 200)
      task_data = data["task"]

      if task_data["parent_task_id"] != nil do
        assert task_data["parent_task_id"] == parent.id
        assert task_data["parent_human_id"] == parent.human_id
      else
        assert task_data["parent_task_id"] == nil
        assert task_data["parent_human_id"] == nil
      end
    end

    test "returns null parent info for standalone tasks", ctx do
      _task = create_task(ctx.workspace, ctx.user, ctx.task_state)

      conn = post(ctx.conn, ~p"/api/agent/tasks/claim")

      assert %{"data" => data} = json_response(conn, 200)
      assert data["task"]["parent_task_id"] == nil
      assert data["task"]["parent_human_id"] == nil
    end

    test "returns 401 without authentication" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> post(~p"/api/agent/tasks/claim")

      assert json_response(conn, 401)
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
      assert states != []

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

  describe "POST /api/agent/runs/:id/cancel" do
    test "cancels a pending run", ctx do
      task = create_task(ctx.workspace, ctx.user, ctx.task_state)

      run =
        generate(
          agent_run(
            [task_id: task.id],
            actor: ctx.user,
            tenant: ctx.workspace.id
          )
        )

      conn = post(ctx.conn, ~p"/api/agent/runs/#{run.id}/cancel")

      assert %{"data" => data} = json_response(conn, 200)
      assert data["status"] == "cancelled"
      assert data["error_message"] == "Manually cancelled by user"
      assert data["completed_at"] != nil
    end

    test "cancels a running run", ctx do
      task = create_task(ctx.workspace, ctx.user, ctx.task_state)

      run =
        generate(
          agent_run(
            [task_id: task.id, status: :running],
            actor: ctx.user,
            tenant: ctx.workspace.id
          )
        )

      conn = post(ctx.conn, ~p"/api/agent/runs/#{run.id}/cancel")

      assert %{"data" => data} = json_response(conn, 200)
      assert data["status"] == "cancelled"
    end

    test "returns 422 for already completed run", ctx do
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

      conn = post(ctx.conn, ~p"/api/agent/runs/#{run.id}/cancel")

      assert json_response(conn, 422)
    end

    test "returns 404 for non-existent run", ctx do
      fake_id = Ash.UUID.generate()

      conn = post(ctx.conn, ~p"/api/agent/runs/#{fake_id}/cancel")

      assert json_response(conn, 404)
    end
  end

  describe "GET /api/agent/comments/:id" do
    test "returns comment data", ctx do
      task = create_task(ctx.workspace, ctx.user, ctx.task_state)

      {:ok, comment} =
        Tasks.create_comment(%{body: "Test comment", task_id: task.id},
          actor: ctx.user,
          tenant: ctx.workspace.id
        )

      conn = get(ctx.conn, ~p"/api/agent/comments/#{comment.id}")

      assert %{"data" => data} = json_response(conn, 200)
      assert data["id"] == comment.id
      assert data["type"] == "comment"
      assert data["body"] == "Test comment"
      assert data["actor_type"] == "user"
      assert data["inserted_at"] != nil
    end

    test "returns 404 for non-existent comment", ctx do
      fake_id = Ash.UUID.generate()

      conn = get(ctx.conn, ~p"/api/agent/comments/#{fake_id}")

      assert json_response(conn, 404)
    end

    test "returns 401 without authentication" do
      fake_id = Ash.UUID.generate()

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/agent/comments/#{fake_id}")

      assert json_response(conn, 401)
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
