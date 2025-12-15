defmodule Citadel.Accounts.ApiKeyAuthTest do
  use Citadel.DataCase, async: true

  import Citadel.Generator

  alias Citadel.Accounts.ApiKey
  alias Citadel.Accounts.User

  # Helper to create an API key bypassing authorization (for test setup)
  defp create_api_key(user, workspace, name, expires_at) do
    ApiKey
    |> Ash.Changeset.for_create(:create, %{
      name: name,
      user_id: user.id,
      workspace_id: workspace.id,
      expires_at: expires_at
    })
    |> Ash.create(authorize?: false)
  end

  describe "API key creation" do
    test "creates an API key with proper hash" do
      user = generate(user())
      workspace = generate(workspace([], actor: user))

      expires_at = DateTime.add(DateTime.utc_now(), 30, :day)

      {:ok, api_key} = create_api_key(user, workspace, "Test API Key", expires_at)

      assert api_key.name == "Test API Key"
      assert api_key.user_id == user.id
      assert api_key.workspace_id == workspace.id
      assert api_key.api_key_hash != nil

      # The API key should have been returned in metadata
      assert api_key.__metadata__[:plaintext_api_key] != nil
      assert String.starts_with?(api_key.__metadata__[:plaintext_api_key], "citadel_")
    end

    test "generated API key can be used to sign in" do
      user = generate(user())
      workspace = generate(workspace([], actor: user))

      expires_at = DateTime.add(DateTime.utc_now(), 30, :day)

      {:ok, api_key} = create_api_key(user, workspace, "Test API Key", expires_at)

      raw_key = api_key.__metadata__[:plaintext_api_key]

      # Sign in with the API key
      {:ok, signed_in_user} =
        User
        |> Ash.Query.for_read(:sign_in_with_api_key, %{api_key: raw_key})
        |> Ash.read_one(authorize?: false)

      assert signed_in_user.id == user.id
    end

    test "expired API key cannot be used to sign in" do
      user = generate(user())
      workspace = generate(workspace([], actor: user))

      # Create an already expired API key
      expired_at = DateTime.add(DateTime.utc_now(), -1, :day)

      {:ok, api_key} = create_api_key(user, workspace, "Expired API Key", expired_at)

      raw_key = api_key.__metadata__[:plaintext_api_key]

      # Try to sign in with expired API key
      # The api_key_relationship filters by valid (expires_at > now()),
      # so expired keys return nil (not found)
      result =
        User
        |> Ash.Query.for_read(:sign_in_with_api_key, %{api_key: raw_key})
        |> Ash.read_one(authorize?: false)

      assert result == {:ok, nil}
    end

    test "invalid API key cannot be used to sign in" do
      # Invalid key format should return nil (not found), not an error
      result =
        User
        |> Ash.Query.for_read(:sign_in_with_api_key, %{api_key: "citadel_invalidkey_checksum"})
        |> Ash.read_one(authorize?: false)

      # The query returns {:ok, nil} for not found, which is expected behavior
      assert result == {:ok, nil}
    end
  end

  describe "API key policies" do
    test "user can only read their own API keys" do
      user1 = generate(user())
      user2 = generate(user())
      workspace1 = generate(workspace([], actor: user1))
      workspace2 = generate(workspace([], actor: user2))

      expires_at = DateTime.add(DateTime.utc_now(), 30, :day)

      # Create API key for user1
      {:ok, _api_key1} = create_api_key(user1, workspace1, "User1 Key", expires_at)

      # Create API key for user2
      {:ok, _api_key2} = create_api_key(user2, workspace2, "User2 Key", expires_at)

      # User1 should only see their own API keys
      {:ok, user1_keys} = Ash.read(ApiKey, actor: user1)
      assert length(user1_keys) == 1
      assert Enum.all?(user1_keys, &(&1.user_id == user1.id))

      # User2 should only see their own API keys
      {:ok, user2_keys} = Ash.read(ApiKey, actor: user2)
      assert length(user2_keys) == 1
      assert Enum.all?(user2_keys, &(&1.user_id == user2.id))
    end

    test "user can delete their own API key" do
      user = generate(user())
      workspace = generate(workspace([], actor: user))

      expires_at = DateTime.add(DateTime.utc_now(), 30, :day)

      {:ok, api_key} = create_api_key(user, workspace, "To Delete", expires_at)

      assert :ok = Ash.destroy(api_key, actor: user)

      # Verify the key no longer exists
      {:ok, keys} = Ash.read(ApiKey, actor: user)
      assert Enum.empty?(keys)
    end
  end

  describe "valid calculation" do
    test "returns true for non-expired API key" do
      user = generate(user())
      workspace = generate(workspace([], actor: user))

      expires_at = DateTime.add(DateTime.utc_now(), 30, :day)

      {:ok, api_key} = create_api_key(user, workspace, "Valid Key", expires_at)

      {:ok, api_key_with_valid} = Ash.load(api_key, :valid, actor: user)
      assert api_key_with_valid.valid == true
    end

    test "returns false for expired API key" do
      user = generate(user())
      workspace = generate(workspace([], actor: user))

      # Create an already expired API key
      expired_at = DateTime.add(DateTime.utc_now(), -1, :day)

      {:ok, api_key} = create_api_key(user, workspace, "Expired Key", expired_at)

      {:ok, api_key_with_valid} = Ash.load(api_key, :valid, actor: user)
      assert api_key_with_valid.valid == false
    end
  end
end
