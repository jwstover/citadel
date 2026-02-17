defmodule Citadel.Accounts.WorkspaceValidationPropertyTest do
  @moduledoc """
  Property-based tests for workspace validation rules.

  These tests verify that validation behaves consistently across
  all edge cases including:
  - Length boundaries (1-100 characters)
  - Whitespace handling
  - Unicode characters
  - Empty and nil values
  """
  use Citadel.DataCase, async: false

  alias Citadel.Accounts

  # Helper to create workspace with org
  defp create_workspace_for_test(name, owner) do
    org = generate(organization([], actor: owner))

    Citadel.Accounts.Workspace
    |> Ash.Changeset.for_create(:create, %{name: name, organization_id: org.id}, actor: owner)
    |> Ash.create()
  end

  describe "workspace name length validation properties" do
    property "workspace names with 1-100 non-whitespace chars always succeed" do
      check all(
              name <- string(:printable, min_length: 1, max_length: 100),
              String.trim(name) != ""
            ) do
        owner = generate(user())

        assert {:ok, workspace} = create_workspace_for_test(name, owner)
        # Name should be trimmed
        assert workspace.name == String.trim(name)
        # Trimmed name should be within bounds
        assert String.length(workspace.name) >= 1
        assert String.length(workspace.name) <= 100
      end
    end

    property "workspace names with 101+ characters always fail" do
      check all(name <- string(:alphanumeric, min_length: 101, max_length: 200)) do
        owner = generate(user())

        assert {:error, %Ash.Error.Invalid{}} = create_workspace_for_test(name, owner)
      end
    end

    property "workspace name at exactly 100 characters succeeds after trim" do
      check all(padding <- string([?\s, ?\t], min_length: 0, max_length: 10)) do
        owner = generate(user())
        # Create name that's exactly 100 chars after trim
        core_name = String.duplicate("A", 100)
        name_with_padding = padding <> core_name

        assert {:ok, workspace} = create_workspace_for_test(name_with_padding, owner)

        assert String.length(workspace.name) == 100
      end
    end
  end

  describe "workspace name whitespace handling properties" do
    property "leading and trailing whitespace is always trimmed" do
      check all(
              name <- string(:printable, min_length: 1, max_length: 90),
              prefix <- string([?\s, ?\t, ?\n, ?\r], max_length: 5),
              suffix <- string([?\s, ?\t, ?\n, ?\r], max_length: 5),
              String.trim(name) != ""
            ) do
        owner = generate(user())

        padded_name = prefix <> name <> suffix

        assert {:ok, workspace} = create_workspace_for_test(padded_name, owner)

        # Whitespace should be trimmed
        assert workspace.name == String.trim(padded_name)
        # Result should not have leading/trailing whitespace
        refute String.starts_with?(workspace.name, " ")
        refute String.ends_with?(workspace.name, " ")
      end
    end

    property "whitespace-only names always fail" do
      check all(whitespace <- string([?\s, ?\t, ?\n, ?\r], min_length: 1, max_length: 50)) do
        owner = generate(user())

        # Whitespace-only should fail (becomes empty after trim)
        assert {:error, %Ash.Error.Invalid{}} = create_workspace_for_test(whitespace, owner)
      end
    end

    property "internal whitespace is preserved" do
      check all(
              part1 <- string(:alphanumeric, min_length: 1, max_length: 40),
              part2 <- string(:alphanumeric, min_length: 1, max_length: 40),
              spaces <- integer(1..5)
            ) do
        owner = generate(user())

        internal_spaces = String.duplicate(" ", spaces)
        name = part1 <> internal_spaces <> part2

        assert {:ok, workspace} = create_workspace_for_test(name, owner)

        # Internal whitespace should be preserved
        assert workspace.name == name
        assert String.contains?(workspace.name, internal_spaces)
      end
    end
  end

  describe "workspace name empty/nil validation properties" do
    property "empty string always fails" do
      check all(_ <- integer(1..25)) do
        owner = generate(user())

        assert {:error, %Ash.Error.Invalid{}} = create_workspace_for_test("", owner)
      end
    end

    property "empty string after trim always fails" do
      check all(whitespace <- string([?\s, ?\t], min_length: 0, max_length: 20)) do
        owner = generate(user())

        # Even with whitespace, empty after trim should fail
        assert {:error, %Ash.Error.Invalid{}} = create_workspace_for_test(whitespace, owner)
      end
    end
  end

  describe "workspace name unicode and special character properties" do
    property "names with unicode characters are handled correctly" do
      check all(
              base <- string(:alphanumeric, min_length: 1, max_length: 40),
              emoji <- member_of(["😀", "🎉", "✅", "🚀", "💻"])
            ) do
        owner = generate(user())

        name = base <> " " <> emoji

        # Unicode should be accepted if within length limits
        case create_workspace_for_test(name, owner) do
          {:ok, workspace} ->
            assert workspace.name == name

          {:error, %Ash.Error.Invalid{}} ->
            # May fail if unicode chars push length over limit
            assert String.length(name) > 100
        end
      end
    end

    property "names with mixed alphanumeric and symbols work" do
      check all(
              base <- string(:alphanumeric, min_length: 1, max_length: 40),
              symbol <- member_of(["-", "_", ".", "@", "#"])
            ) do
        owner = generate(user())

        name = base <> symbol <> "test"

        assert {:ok, workspace} = create_workspace_for_test(name, owner)
        assert workspace.name == name
      end
    end
  end

  describe "workspace name update validation properties" do
    property "updating to valid names always succeeds" do
      check all(
              initial_name <- string(:printable, min_length: 1, max_length: 90),
              new_name <- string(:printable, min_length: 1, max_length: 90),
              String.trim(initial_name) != "",
              String.trim(new_name) != ""
            ) do
        owner = generate(user())

        # Create workspace
        {:ok, workspace} = create_workspace_for_test(initial_name, owner)

        # Update should succeed with valid name
        assert {:ok, updated} =
                 Accounts.update_workspace(workspace, %{name: new_name}, actor: owner)

        assert updated.name == String.trim(new_name)
      end
    end

    property "updating to invalid names always fails" do
      check all(
              initial_name <- string(:printable, min_length: 1, max_length: 90),
              invalid_name <-
                one_of([
                  constant(""),
                  string([?\s, ?\t, ?\n, ?\r], min_length: 1, max_length: 20),
                  string(:alphanumeric, min_length: 101, max_length: 150)
                ]),
              String.trim(initial_name) != ""
            ) do
        owner = generate(user())

        # Create workspace
        {:ok, workspace} = create_workspace_for_test(initial_name, owner)

        # Update should fail with invalid name
        assert {:error, %Ash.Error.Invalid{}} =
                 Accounts.update_workspace(
                   workspace,
                   %{name: invalid_name},
                   actor: owner
                 )

        # Original name should be unchanged
        {:ok, unchanged} = Accounts.get_workspace_by_id(workspace.id, actor: owner)
        assert unchanged.name == String.trim(initial_name)
      end
    end
  end

  describe "workspace name boundary conditions" do
    property "exactly at min length (1 char after trim) succeeds" do
      check all(
              char <- string(:alphanumeric, length: 1),
              padding <- string([?\s, ?\t], max_length: 10)
            ) do
        owner = generate(user())

        name = padding <> char

        assert {:ok, workspace} = create_workspace_for_test(name, owner)
        assert String.length(workspace.name) == 1
      end
    end

    property "exactly at max length (100 chars) succeeds" do
      check all(_ <- integer(1..50)) do
        owner = generate(user())

        name = String.duplicate("A", 100)

        assert {:ok, workspace} = create_workspace_for_test(name, owner)
        assert String.length(workspace.name) == 100
      end
    end

    property "one char over max length (101 chars) fails" do
      check all(_ <- integer(1..50)) do
        owner = generate(user())

        name = String.duplicate("A", 101)

        assert {:error, %Ash.Error.Invalid{}} = create_workspace_for_test(name, owner)
      end
    end
  end
end
