defmodule CitadelWeb.Api.AgentRefinementTest do
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

    task =
      generate(
        task(
          [workspace_id: workspace.id, task_state_id: task_state.id, agent_eligible: true],
          actor: user,
          tenant: workspace.id
        )
      )

    run =
      generate(
        agent_run(
          [task_id: task.id, status: :running],
          actor: user,
          tenant: workspace.id
        )
      )

    %{conn: conn, user: user, workspace: workspace, task: task, run: run}
  end

  describe "POST /api/agent/runs/:run_id/refinement" do
    test "creates a refinement cycle for a running run", ctx do
      conn =
        post(ctx.conn, ~p"/api/agent/runs/#{ctx.run.id}/refinement", %{
          "max_iterations" => 5,
          "evaluator_config" => %{"type" => "test_runner"}
        })

      assert %{"data" => data} = json_response(conn, 201)
      assert data["agent_run_id"] == ctx.run.id
      assert data["status"] == "running"
      assert data["max_iterations"] == 5
      assert data["current_iteration"] == 0
      assert data["evaluator_config"] == %{"type" => "test_runner"}
      assert data["final_score"] == nil
      assert data["id"] != nil
    end

    test "uses default max_iterations when not provided", ctx do
      conn = post(ctx.conn, ~p"/api/agent/runs/#{ctx.run.id}/refinement", %{})

      assert %{"data" => data} = json_response(conn, 201)
      assert data["max_iterations"] == 3
    end

    test "rejects cycle creation for non-running run", ctx do
      completed_run =
        generate(
          agent_run(
            [task_id: ctx.task.id, status: :completed],
            actor: ctx.user,
            tenant: ctx.workspace.id
          )
        )

      conn = post(ctx.conn, ~p"/api/agent/runs/#{completed_run.id}/refinement", %{})

      assert %{"errors" => %{"detail" => "Run is not in running status"}} =
               json_response(conn, 422)
    end

    test "rejects duplicate active cycle", ctx do
      _first = post(ctx.conn, ~p"/api/agent/runs/#{ctx.run.id}/refinement", %{})

      conn = post(ctx.conn, ~p"/api/agent/runs/#{ctx.run.id}/refinement", %{})

      assert %{"errors" => %{"detail" => detail}} = json_response(conn, 409)
      assert detail =~ "active refinement cycle already exists"
    end

    test "returns 404 for non-existent run", ctx do
      fake_id = Ash.UUID.generate()
      conn = post(ctx.conn, ~p"/api/agent/runs/#{fake_id}/refinement", %{})

      assert json_response(conn, 404)
    end
  end

  describe "POST /api/agent/runs/:run_id/refinement/iterations" do
    setup ctx do
      conn =
        post(ctx.conn, ~p"/api/agent/runs/#{ctx.run.id}/refinement", %{
          "max_iterations" => 3
        })

      %{"data" => %{"id" => cycle_id}} = json_response(conn, 201)

      %{cycle_id: cycle_id}
    end

    test "creates an iteration with score and feedback", ctx do
      conn =
        post(ctx.conn, ~p"/api/agent/runs/#{ctx.run.id}/refinement/iterations", %{
          "iteration_number" => 1,
          "score" => 0.6,
          "evaluation_result" => %{"tests_passed" => 5, "tests_failed" => 3},
          "feedback" => "Tests failed: 3 out of 8",
          "status" => "evaluated"
        })

      assert %{"data" => data} = json_response(conn, 201)
      assert data["refinement_cycle_id"] == ctx.cycle_id
      assert data["iteration_number"] == 1
      assert data["score"] == 0.6
      assert data["feedback"] == "Tests failed: 3 out of 8"
      assert data["status"] == "evaluated"
      assert data["evaluation_result"] == %{"tests_passed" => 5, "tests_failed" => 3}
    end

    test "publishes PubSub event on iteration creation", ctx do
      Phoenix.PubSub.subscribe(Citadel.PubSub, "tasks:refinement:#{ctx.run.id}")

      post(ctx.conn, ~p"/api/agent/runs/#{ctx.run.id}/refinement/iterations", %{
        "iteration_number" => 1,
        "score" => 0.7,
        "feedback" => "Almost passing",
        "status" => "evaluated"
      })

      assert_receive %{
        event: "iteration_created",
        iteration: %{number: 1, score: 0.7, feedback: "Almost passing", status: :evaluated}
      }
    end

    test "updates cycle current_iteration on iteration creation", ctx do
      post(ctx.conn, ~p"/api/agent/runs/#{ctx.run.id}/refinement/iterations", %{
        "iteration_number" => 2,
        "score" => 0.8,
        "status" => "evaluated"
      })

      {:ok, cycle} =
        Tasks.get_refinement_cycle(ctx.cycle_id,
          authorize?: false,
          tenant: ctx.workspace.id
        )

      assert cycle.current_iteration == 2
    end

    test "returns 404 for non-existent run", ctx do
      fake_id = Ash.UUID.generate()

      conn =
        post(ctx.conn, ~p"/api/agent/runs/#{fake_id}/refinement/iterations", %{
          "iteration_number" => 1,
          "score" => 0.5,
          "status" => "evaluated"
        })

      assert json_response(conn, 404)
    end

    test "returns 422 when no active cycle exists", ctx do
      {:ok, cycle} =
        Tasks.get_refinement_cycle(ctx.cycle_id,
          authorize?: false,
          tenant: ctx.workspace.id
        )

      Tasks.complete_refinement_cycle!(cycle, %{final_score: 1.0},
        authorize?: false,
        tenant: ctx.workspace.id
      )

      conn =
        post(ctx.conn, ~p"/api/agent/runs/#{ctx.run.id}/refinement/iterations", %{
          "iteration_number" => 1,
          "score" => 0.5,
          "status" => "evaluated"
        })

      assert %{"errors" => %{"detail" => detail}} = json_response(conn, 422)
      assert detail =~ "No active refinement cycle"
    end
  end

  describe "PATCH /api/agent/runs/:run_id/refinement" do
    setup ctx do
      conn =
        post(ctx.conn, ~p"/api/agent/runs/#{ctx.run.id}/refinement", %{
          "max_iterations" => 3
        })

      %{"data" => %{"id" => cycle_id}} = json_response(conn, 201)

      %{cycle_id: cycle_id}
    end

    test "completes cycle with passed status", ctx do
      conn =
        patch(ctx.conn, ~p"/api/agent/runs/#{ctx.run.id}/refinement", %{
          "status" => "passed",
          "final_score" => 0.95
        })

      assert %{"data" => data} = json_response(conn, 200)
      assert data["status"] == "passed"
      assert data["final_score"] == 0.95
    end

    test "fails cycle with failed_max_iterations status", ctx do
      conn =
        patch(ctx.conn, ~p"/api/agent/runs/#{ctx.run.id}/refinement", %{
          "status" => "failed_max_iterations",
          "final_score" => 0.4
        })

      assert %{"data" => data} = json_response(conn, 200)
      assert data["status"] == "failed_max_iterations"
    end

    test "fails cycle with error status", ctx do
      conn =
        patch(ctx.conn, ~p"/api/agent/runs/#{ctx.run.id}/refinement", %{
          "status" => "error"
        })

      assert %{"data" => data} = json_response(conn, 200)
      assert data["status"] == "error"
    end

    test "publishes PubSub event on cycle completion", ctx do
      Phoenix.PubSub.subscribe(Citadel.PubSub, "tasks:refinement:#{ctx.run.id}")

      patch(ctx.conn, ~p"/api/agent/runs/#{ctx.run.id}/refinement", %{
        "status" => "passed",
        "final_score" => 0.9
      })

      assert_receive %{
        event: "cycle_completed",
        status: :passed,
        final_score: 0.9
      }
    end

    test "returns 404 for non-existent run", ctx do
      fake_id = Ash.UUID.generate()

      conn =
        patch(ctx.conn, ~p"/api/agent/runs/#{fake_id}/refinement", %{
          "status" => "passed",
          "final_score" => 0.9
        })

      assert json_response(conn, 404)
    end

    test "returns 422 when no active cycle exists", ctx do
      {:ok, cycle} =
        Tasks.get_refinement_cycle(ctx.cycle_id,
          authorize?: false,
          tenant: ctx.workspace.id
        )

      Tasks.complete_refinement_cycle!(cycle, %{final_score: 1.0},
        authorize?: false,
        tenant: ctx.workspace.id
      )

      conn =
        patch(ctx.conn, ~p"/api/agent/runs/#{ctx.run.id}/refinement", %{
          "status" => "passed",
          "final_score" => 0.9
        })

      assert %{"errors" => %{"detail" => detail}} = json_response(conn, 422)
      assert detail =~ "No active refinement cycle"
    end

    test "returns 422 for invalid status", ctx do
      conn =
        patch(ctx.conn, ~p"/api/agent/runs/#{ctx.run.id}/refinement", %{
          "status" => "invalid_status"
        })

      assert json_response(conn, 422)
    end
  end
end
