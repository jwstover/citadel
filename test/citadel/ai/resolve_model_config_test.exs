defmodule Citadel.AI.ResolveModelConfigTest do
  use Citadel.DataCase, async: true

  import Mox

  alias Citadel.AI.Config

  setup :verify_on_exit!

  setup do
    user = generate(user())
    workspace = generate(workspace([], actor: user))
    {:ok, user: user, workspace: workspace}
  end

  describe "resolve_model_config/1" do
    test "returns system defaults when no options provided" do
      Citadel.AI.MockProvider
      |> expect(:default_model, fn -> "test-model" end)

      assert {:ok, config} = Config.resolve_model_config([])
      assert config.provider == Config.default_provider()
      assert config.model == "test-model"
      assert config.temperature == 0.7
      assert is_nil(config.max_tokens)
    end

    test "returns specific model config when model_config_id is provided", %{
      user: user,
      workspace: workspace
    } do
      mc =
        generate(
          model_config(
            [
              workspace_id: workspace.id,
              provider: :openai,
              model: "gpt-4o",
              temperature: 0.5,
              max_tokens: 4096
            ],
            actor: user,
            tenant: workspace.id
          )
        )

      assert {:ok, config} = Config.resolve_model_config(model_config_id: mc.id)
      assert config.provider == :openai
      assert config.model == "gpt-4o"
      assert config.temperature == 0.5
      assert config.max_tokens == 4096
    end

    test "returns workspace default when workspace_id is provided", %{
      user: user,
      workspace: workspace
    } do
      mc =
        generate(
          model_config(
            [
              workspace_id: workspace.id,
              provider: :anthropic,
              model: "claude-sonnet-4-20250514",
              temperature: 0.3
            ],
            actor: user,
            tenant: workspace.id
          )
        )

      Citadel.Tasks.set_model_config_default!(mc, actor: user, tenant: workspace.id)

      assert {:ok, config} = Config.resolve_model_config(workspace_id: workspace.id)
      assert config.provider == :anthropic
      assert config.model == "claude-sonnet-4-20250514"
      assert config.temperature == 0.3
    end

    test "returns system defaults when workspace has no default model config", %{
      workspace: workspace
    } do
      Citadel.AI.MockProvider
      |> expect(:default_model, fn -> "test-model" end)

      assert {:ok, config} = Config.resolve_model_config(workspace_id: workspace.id)
      assert config.provider == Config.default_provider()
      assert config.model == "test-model"
    end

    test "model_config_id takes priority over workspace_id", %{
      user: user,
      workspace: workspace
    } do
      default_mc =
        generate(
          model_config(
            [workspace_id: workspace.id, provider: :anthropic, model: "claude-sonnet-4-20250514"],
            actor: user,
            tenant: workspace.id
          )
        )

      Citadel.Tasks.set_model_config_default!(default_mc, actor: user, tenant: workspace.id)

      specific_mc =
        generate(
          model_config(
            [workspace_id: workspace.id, provider: :openai, model: "gpt-4o"],
            actor: user,
            tenant: workspace.id
          )
        )

      assert {:ok, config} =
               Config.resolve_model_config(
                 model_config_id: specific_mc.id,
                 workspace_id: workspace.id
               )

      assert config.provider == :openai
      assert config.model == "gpt-4o"
    end

    test "returns error for non-existent model_config_id" do
      assert {:error, _} =
               Config.resolve_model_config(model_config_id: Ash.UUID.generate())
    end
  end
end
