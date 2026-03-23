defmodule CitadelAgent.RunnerSessionIdTest do
  use ExUnit.Case, async: true

  describe "extract_session_id_from_stream_json/1" do
    test "extracts session_id from result line" do
      output = """
      {"type":"assistant","message":{"content":[{"type":"text","text":"Hello"}]}}
      {"type":"result","subtype":"success","session_id":"abc-123","is_error":false}
      """

      assert CitadelAgent.Runner.extract_session_id_from_stream_json(output) == "abc-123"
    end

    test "returns nil when no result line exists" do
      output = """
      {"type":"assistant","message":{"content":[{"type":"text","text":"Hello"}]}}
      {"type":"content_block_delta","delta":{"text":"world"}}
      """

      assert CitadelAgent.Runner.extract_session_id_from_stream_json(output) == nil
    end

    test "returns nil when result has no session_id" do
      output = """
      {"type":"result","subtype":"success","is_error":false}
      """

      assert CitadelAgent.Runner.extract_session_id_from_stream_json(output) == nil
    end

    test "handles empty output" do
      assert CitadelAgent.Runner.extract_session_id_from_stream_json("") == nil
    end

    test "handles non-JSON lines mixed in" do
      output = """
      some debug text
      {"type":"result","session_id":"sess-456","subtype":"success"}
      more text
      """

      assert CitadelAgent.Runner.extract_session_id_from_stream_json(output) == "sess-456"
    end
  end
end
