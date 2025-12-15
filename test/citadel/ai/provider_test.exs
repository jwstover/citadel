defmodule Citadel.AI.ProviderTest do
  use ExUnit.Case, async: true

  alias Citadel.AI.Provider

  describe "classify_http_error/1" do
    test "classifies 401 as authentication_error" do
      assert Provider.classify_http_error(401) == :authentication_error
    end

    test "classifies 429 as rate_limit_error" do
      assert Provider.classify_http_error(429) == :rate_limit_error
    end

    test "classifies 400 as invalid_request_error" do
      assert Provider.classify_http_error(400) == :invalid_request_error
    end

    test "classifies 500 as api_error" do
      assert Provider.classify_http_error(500) == :api_error
    end

    test "classifies unknown status codes as api_error" do
      assert Provider.classify_http_error(502) == :api_error
      assert Provider.classify_http_error(503) == :api_error
      assert Provider.classify_http_error(422) == :api_error
    end
  end

  describe "format_error/2" do
    test "formats authentication_error" do
      result = Provider.format_error(:authentication_error, "Invalid API key")
      assert result == "Authentication failed: Invalid API key"
    end

    test "formats rate_limit_error" do
      result = Provider.format_error(:rate_limit_error, "Too many requests")
      assert result == "Rate limit exceeded: Too many requests"
    end

    test "formats invalid_request_error" do
      result = Provider.format_error(:invalid_request_error, "Bad params")
      assert result == "Invalid request: Bad params"
    end

    test "formats api_error" do
      result = Provider.format_error(:api_error, "Server error")
      assert result == "API error: Server error"
    end

    test "formats timeout_error" do
      result = Provider.format_error(:timeout_error, "Connection timed out")
      assert result == "Request timed out: Connection timed out"
    end

    test "formats unknown_error" do
      result = Provider.format_error(:unknown_error, "Something went wrong")
      assert result == "Unknown error: Something went wrong"
    end
  end
end
