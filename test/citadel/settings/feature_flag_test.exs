defmodule Citadel.Settings.FeatureFlagTest do
  use Citadel.DataCase, async: false

  alias Citadel.Settings

  describe "feature flag creation" do
    test "creates a feature flag with valid attributes" do
      attrs = %{
        key: :api_access,
        enabled: true,
        description: "Enable API access globally"
      }

      assert {:ok, flag} = Settings.create_feature_flag(attrs, authorize?: false)
      assert flag.key == :api_access
      assert flag.enabled == true
      assert flag.description == "Enable API access globally"
    end

    test "creates a disabled feature flag" do
      attrs = %{
        key: :data_export,
        enabled: false,
        description: "Temporarily disable data export"
      }

      assert {:ok, flag} = Settings.create_feature_flag(attrs, authorize?: false)
      assert flag.key == :data_export
      assert flag.enabled == false
    end

    test "defaults enabled to false if not specified" do
      attrs = %{
        key: :webhooks
      }

      assert {:ok, flag} = Settings.create_feature_flag(attrs, authorize?: false)
      assert flag.enabled == false
    end

    test "creates flag with non-billing key" do
      non_billing_key = :"test_feature_#{System.unique_integer([:positive])}"

      attrs = %{
        key: non_billing_key,
        enabled: true,
        description: "Test operational feature"
      }

      assert {:ok, flag} = Settings.create_feature_flag(attrs, authorize?: false)
      assert flag.key == non_billing_key
      assert flag.enabled == true
    end

    test "creates flag with billing feature key" do
      attrs = %{
        key: :api_access,
        enabled: false,
        description: "Override tier access for testing"
      }

      assert {:ok, flag} = Settings.create_feature_flag(attrs, authorize?: false)
      assert flag.key == :api_access
      assert flag.enabled == false
    end

    test "enforces unique key constraint" do
      attrs = %{key: :api_access, enabled: true}

      assert {:ok, _flag1} = Settings.create_feature_flag(attrs, authorize?: false)

      assert {:error, %Ash.Error.Invalid{}} =
               Settings.create_feature_flag(attrs, authorize?: false)
    end
  end

  describe "feature flag updates" do
    test "updates enabled status" do
      {:ok, flag} =
        Settings.create_feature_flag(%{key: :bulk_import, enabled: false}, authorize?: false)

      assert {:ok, updated} =
               Settings.update_feature_flag(flag, %{enabled: true}, authorize?: false)

      assert updated.enabled == true
    end

    test "updates description" do
      {:ok, flag} =
        Settings.create_feature_flag(%{key: :custom_branding, enabled: true}, authorize?: false)

      assert {:ok, updated} =
               Settings.update_feature_flag(flag, %{description: "Updated description"},
                 authorize?: false
               )

      assert updated.description == "Updated description"
    end

    test "cannot update key after creation" do
      {:ok, flag} =
        Settings.create_feature_flag(%{key: :priority_support, enabled: true}, authorize?: false)

      # Key is not accepted in update action, so passing it should error
      assert {:error, %Ash.Error.Invalid{}} =
               Settings.update_feature_flag(flag, %{key: :different_key, enabled: false},
                 authorize?: false
               )
    end
  end

  describe "feature flag deletion" do
    test "deletes a feature flag" do
      {:ok, flag} =
        Settings.create_feature_flag(%{key: :advanced_ai_models, enabled: true},
          authorize?: false
        )

      assert :ok = Settings.delete_feature_flag(flag, authorize?: false)

      assert {:error, %Ash.Error.Invalid{}} =
               Settings.get_feature_flag_by_key(:advanced_ai_models, authorize?: false)
    end
  end

  describe "feature flag queries" do
    test "gets feature flag by key" do
      {:ok, flag} = Settings.create_feature_flag(%{key: :byok, enabled: true}, authorize?: false)

      assert {:ok, fetched} = Settings.get_feature_flag_by_key(:byok, authorize?: false)
      assert fetched.id == flag.id
      assert fetched.key == :byok
    end

    test "lists all feature flags" do
      Settings.create_feature_flag(%{key: :api_access, enabled: true}, authorize?: false)
      Settings.create_feature_flag(%{key: :webhooks, enabled: false}, authorize?: false)

      {:ok, flags} = Settings.list_feature_flags(authorize?: false)
      assert length(flags) >= 2
      assert Enum.any?(flags, fn f -> f.key == :api_access end)
      assert Enum.any?(flags, fn f -> f.key == :webhooks end)
    end
  end
end
