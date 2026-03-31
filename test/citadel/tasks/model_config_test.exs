defmodule Citadel.Tasks.ModelConfigTest do
  use Citadel.DataCase, async: true

  alias Citadel.Tasks

  setup do
    user = generate(user())
    workspace = generate(workspace([], actor: user))
    %{user: user, workspace: workspace}
  end

  describe "create_model_config/2" do
    test "creates a model config with valid attributes", %{user: user, workspace: workspace} do
      config =
        Tasks.create_model_config!(
          %{
            name: "Claude Sonnet",
            provider: :anthropic,
            model: "claude-sonnet-4-20250514",
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      assert config.name == "Claude Sonnet"
      assert config.provider == :anthropic
      assert config.model == "claude-sonnet-4-20250514"
      assert config.temperature == 0.7
      assert config.is_default == false
      assert is_nil(config.max_tokens)
    end

    test "creates a model config with all optional fields", %{user: user, workspace: workspace} do
      config =
        Tasks.create_model_config!(
          %{
            name: "GPT-4o Custom",
            provider: :openai,
            model: "gpt-4o",
            temperature: 0.3,
            max_tokens: 4096,
            is_default: true,
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )

      assert config.temperature == 0.3
      assert config.max_tokens == 4096
      assert config.is_default == true
    end

    test "raises on invalid provider", %{user: user, workspace: workspace} do
      assert_raise Ash.Error.Invalid, fn ->
        Tasks.create_model_config!(
          %{
            name: "Bad Provider",
            provider: :gemini,
            model: "gemini-pro",
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )
      end
    end

    test "raises when name is missing", %{user: user, workspace: workspace} do
      assert_raise Ash.Error.Invalid, fn ->
        Tasks.create_model_config!(
          %{provider: :anthropic, model: "claude-sonnet-4-20250514", workspace_id: workspace.id},
          actor: user,
          tenant: workspace.id
        )
      end
    end

    test "enforces unique name per workspace", %{user: user, workspace: workspace} do
      Tasks.create_model_config!(
        %{
          name: "Duplicate Name",
          provider: :anthropic,
          model: "claude-sonnet-4-20250514",
          workspace_id: workspace.id
        },
        actor: user,
        tenant: workspace.id
      )

      assert_raise Ash.Error.Invalid, fn ->
        Tasks.create_model_config!(
          %{
            name: "Duplicate Name",
            provider: :openai,
            model: "gpt-4o",
            workspace_id: workspace.id
          },
          actor: user,
          tenant: workspace.id
        )
      end
    end
  end

  describe "list_model_configs/1" do
    test "lists all configs for a workspace", %{user: user, workspace: workspace} do
      generate(model_config([workspace_id: workspace.id], actor: user, tenant: workspace.id))
      generate(model_config([workspace_id: workspace.id], actor: user, tenant: workspace.id))

      configs = Tasks.list_model_configs!(actor: user, tenant: workspace.id)
      assert length(configs) == 2
    end

    test "does not return configs from other workspaces", %{user: user, workspace: workspace} do
      other_workspace = generate(workspace([], actor: user))

      generate(model_config([workspace_id: workspace.id], actor: user, tenant: workspace.id))

      generate(
        model_config([workspace_id: other_workspace.id],
          actor: user,
          tenant: other_workspace.id
        )
      )

      configs = Tasks.list_model_configs!(actor: user, tenant: workspace.id)
      assert length(configs) == 1
    end
  end

  describe "update_model_config/3" do
    test "updates name and model", %{user: user, workspace: workspace} do
      config =
        generate(model_config([workspace_id: workspace.id], actor: user, tenant: workspace.id))

      updated =
        Tasks.update_model_config!(config, %{name: "Updated Name", model: "gpt-4o"},
          actor: user,
          tenant: workspace.id
        )

      assert updated.name == "Updated Name"
      assert updated.model == "gpt-4o"
    end
  end

  describe "destroy_model_config/2" do
    test "destroys a model config", %{user: user, workspace: workspace} do
      config =
        generate(model_config([workspace_id: workspace.id], actor: user, tenant: workspace.id))

      :ok = Tasks.destroy_model_config!(config, actor: user, tenant: workspace.id)

      configs = Tasks.list_model_configs!(actor: user, tenant: workspace.id)
      assert configs == []
    end
  end

  describe "set_model_config_default/2" do
    test "sets a config as default", %{user: user, workspace: workspace} do
      config =
        generate(model_config([workspace_id: workspace.id], actor: user, tenant: workspace.id))

      updated =
        Tasks.set_model_config_default!(config, actor: user, tenant: workspace.id)

      assert updated.is_default == true
    end

    test "unsets previous default when setting a new one", %{user: user, workspace: workspace} do
      config1 =
        generate(
          model_config([workspace_id: workspace.id, is_default: true],
            actor: user,
            tenant: workspace.id
          )
        )

      config2 =
        generate(model_config([workspace_id: workspace.id], actor: user, tenant: workspace.id))

      Tasks.set_model_config_default!(config2, actor: user, tenant: workspace.id)

      reloaded_config1 =
        Tasks.get_model_config!(config1.id, actor: user, tenant: workspace.id)

      reloaded_config2 =
        Tasks.get_model_config!(config2.id, actor: user, tenant: workspace.id)

      assert reloaded_config1.is_default == false
      assert reloaded_config2.is_default == true
    end

    test "only one default exists at a time across multiple configs", %{
      user: user,
      workspace: workspace
    } do
      config1 =
        generate(model_config([workspace_id: workspace.id], actor: user, tenant: workspace.id))

      config2 =
        generate(model_config([workspace_id: workspace.id], actor: user, tenant: workspace.id))

      config3 =
        generate(model_config([workspace_id: workspace.id], actor: user, tenant: workspace.id))

      Tasks.set_model_config_default!(config1, actor: user, tenant: workspace.id)
      Tasks.set_model_config_default!(config2, actor: user, tenant: workspace.id)
      Tasks.set_model_config_default!(config3, actor: user, tenant: workspace.id)

      configs = Tasks.list_model_configs!(actor: user, tenant: workspace.id)
      defaults = Enum.filter(configs, & &1.is_default)
      assert length(defaults) == 1
      assert hd(defaults).id == config3.id
    end
  end

  describe "get_workspace_default_model_config/1" do
    test "returns the default config", %{user: user, workspace: workspace} do
      generate(model_config([workspace_id: workspace.id], actor: user, tenant: workspace.id))

      config2 =
        generate(
          model_config([workspace_id: workspace.id, is_default: true],
            actor: user,
            tenant: workspace.id
          )
        )

      default =
        Tasks.get_workspace_default_model_config!(actor: user, tenant: workspace.id)

      assert default.id == config2.id
    end

    test "raises not found when no default exists", %{user: user, workspace: workspace} do
      generate(model_config([workspace_id: workspace.id], actor: user, tenant: workspace.id))

      assert_raise Ash.Error.Invalid, fn ->
        Tasks.get_workspace_default_model_config!(actor: user, tenant: workspace.id)
      end
    end
  end

  describe "authorization" do
    test "non-member cannot list configs", %{user: user, workspace: workspace} do
      generate(model_config([workspace_id: workspace.id], actor: user, tenant: workspace.id))
      other_user = generate(user())

      configs = Tasks.list_model_configs!(actor: other_user, tenant: workspace.id)
      assert configs == []
    end

    test "non-member cannot create configs", %{workspace: workspace} do
      other_user = generate(user())

      assert_raise Ash.Error.Forbidden, fn ->
        Tasks.create_model_config!(
          %{
            name: "Unauthorized",
            provider: :anthropic,
            model: "claude-sonnet-4-20250514",
            workspace_id: workspace.id
          },
          actor: other_user,
          tenant: workspace.id
        )
      end
    end
  end
end
