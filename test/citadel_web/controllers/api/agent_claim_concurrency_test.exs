defmodule CitadelWeb.Api.AgentClaimConcurrencyTest do
  use CitadelWeb.ConnCase, async: false

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

    %{raw_key: raw_key, user: user, workspace: workspace, task_state: task_state}
  end

  defp create_task(workspace, user, task_state, attrs \\ []) do
    defaults = [workspace_id: workspace.id, task_state_id: task_state.id, agent_eligible: true]
    generate(task(Keyword.merge(defaults, attrs), actor: user, tenant: workspace.id))
  end

  defp claim_request(raw_key) do
    build_conn()
    |> put_req_header("authorization", "Bearer #{raw_key}")
    |> put_req_header("accept", "application/json")
    |> post(~p"/api/agent/tasks/claim")
  end

  describe "concurrent POST /api/agent/tasks/claim" do
    test "5 concurrent claims for 1 task yield exactly 1 winner", ctx do
      _task = create_task(ctx.workspace, ctx.user, ctx.task_state)

      results =
        1..5
        |> Enum.map(fn _ ->
          Task.async(fn -> claim_request(ctx.raw_key) end)
        end)
        |> Enum.map(&Task.await/1)

      statuses = Enum.map(results, & &1.status)
      assert Enum.count(statuses, &(&1 == 200)) == 1
      assert Enum.count(statuses, &(&1 == 204)) == 4
    end

    test "N concurrent claims for M tasks yield exactly M winners", ctx do
      num_tasks = 3
      num_claimers = 8

      tasks =
        for _ <- 1..num_tasks do
          create_task(ctx.workspace, ctx.user, ctx.task_state)
        end

      results =
        1..num_claimers
        |> Enum.map(fn _ ->
          Task.async(fn -> claim_request(ctx.raw_key) end)
        end)
        |> Enum.map(&Task.await/1)

      statuses = Enum.map(results, & &1.status)
      winners = Enum.count(statuses, &(&1 == 200))
      losers = Enum.count(statuses, &(&1 == 204))

      assert winners == num_tasks
      assert losers == num_claimers - num_tasks

      won_task_ids =
        results
        |> Enum.filter(&(&1.status == 200))
        |> Enum.map(fn conn ->
          body = Jason.decode!(conn.resp_body)
          body["data"]["task"]["id"]
        end)

      assert length(Enum.uniq(won_task_ids)) == num_tasks
      assert MapSet.subset?(MapSet.new(won_task_ids), MapSet.new(Enum.map(tasks, & &1.id)))
    end

    test "tasks with existing running runs are never claimed", ctx do
      task = create_task(ctx.workspace, ctx.user, ctx.task_state)

      generate(
        agent_run(
          [task_id: task.id, status: :running],
          actor: ctx.user,
          tenant: ctx.workspace.id
        )
      )

      results =
        1..5
        |> Enum.map(fn _ ->
          Task.async(fn -> claim_request(ctx.raw_key) end)
        end)
        |> Enum.map(&Task.await/1)

      statuses = Enum.map(results, & &1.status)
      assert Enum.all?(statuses, &(&1 == 204))
    end
  end
end
