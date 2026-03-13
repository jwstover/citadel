defmodule CitadelAgent.RunnerPrDescriptionTest do
  use ExUnit.Case, async: true

  describe "generate_pr_description/2" do
    @moduletag :tmp_dir

    setup %{tmp_dir: tmp_dir} do
      System.cmd("git", ["init", "-b", "main"], cd: tmp_dir)
      {:ok, project_path: tmp_dir}
    end

    test "returns fallback description when CLI is unavailable", %{project_path: project_path} do
      task = %{
        "human_id" => "TEST-PR-1",
        "title" => "Add user settings page",
        "description" => "Create a new settings page for users"
      }

      assert {:ok, description} = CitadelAgent.Runner.generate_pr_description(task, project_path)
      assert is_binary(description)
      assert String.length(description) > 0
    end

    test "returns fallback with task title on error", %{project_path: project_path} do
      task = %{
        "human_id" => "TEST-PR-2",
        "title" => "Fix login bug",
        "description" => nil
      }

      assert {:ok, description} = CitadelAgent.Runner.generate_pr_description(task, project_path)
      assert description =~ "Fix login bug"
    end

    test "handles task with nil title gracefully", %{project_path: project_path} do
      task = %{
        "human_id" => "TEST-PR-3",
        "title" => nil,
        "description" => nil
      }

      assert {:ok, description} = CitadelAgent.Runner.generate_pr_description(task, project_path)
      assert is_binary(description)
    end
  end

  describe "extract_text_from_stream_json/1" do
    test "extracts text from result type" do
      output = ~s|{"type":"result","result":{"content":[{"type":"text","text":"## Summary\\nFixes the login bug"}]}}|

      assert CitadelAgent.Runner.extract_text_from_stream_json(output) ==
               "## Summary\nFixes the login bug"
    end

    test "extracts text from assistant message type" do
      output = ~s|{"type":"assistant","message":{"content":[{"type":"text","text":"PR description here"}]}}|

      assert CitadelAgent.Runner.extract_text_from_stream_json(output) == "PR description here"
    end

    test "extracts text from content_block_delta events" do
      output = """
      {"type":"content_block_delta","delta":{"text":"Hello "}}
      {"type":"content_block_delta","delta":{"text":"world"}}
      """

      assert CitadelAgent.Runner.extract_text_from_stream_json(output) == "Hello world"
    end

    test "returns nil for empty output" do
      assert CitadelAgent.Runner.extract_text_from_stream_json("") == nil
    end

    test "returns nil when no text content found" do
      output = ~s|{"type":"system","message":"starting"}|
      assert CitadelAgent.Runner.extract_text_from_stream_json(output) == nil
    end

    test "ignores non-JSON lines" do
      output = """
      not json
      {"type":"result","result":{"content":[{"type":"text","text":"good output"}]}}
      also not json
      """

      assert CitadelAgent.Runner.extract_text_from_stream_json(output) == "good output"
    end
  end
end
