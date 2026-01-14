defmodule Citadel.Integrations.GitHubTest do
  use ExUnit.Case, async: true

  alias Citadel.Integrations.GitHub

  describe "validate_token/1" do
    test "returns error for nil token" do
      assert GitHub.validate_token(nil) == {:error, :invalid_token}
    end

    test "returns error for empty string token" do
      assert GitHub.validate_token("") == {:error, :invalid_token}
    end

    test "returns error for non-string token" do
      assert GitHub.validate_token(123) == {:error, :invalid_token}
      assert GitHub.validate_token(%{}) == {:error, :invalid_token}
    end

    # Note: Integration tests that actually call GitHub's API are in
    # docs/testing/github_mcp_manual_testing.md
    #
    # To test with a real token:
    #   1. Set GITHUB_TEST_TOKEN environment variable
    #   2. Run: mix test test/citadel/integrations/github_test.exs --only integration
    @tag :integration
    @tag :skip
    test "validates real token" do
      token = System.get_env("GITHUB_TEST_TOKEN")

      if token do
        assert {:ok, %{login: login}} = GitHub.validate_token(token)
        assert is_binary(login)
      else
        flunk("GITHUB_TEST_TOKEN environment variable not set")
      end
    end
  end
end
