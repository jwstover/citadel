defmodule Citadel.AI.SchemaNormalizerTest do
  use ExUnit.Case, async: true

  alias Citadel.AI.SchemaNormalizer

  describe "normalize_schema/1" do
    test "adds additionalProperties: false to top-level object" do
      schema = %{"type" => "object", "properties" => %{"name" => %{"type" => "string"}}}

      result = SchemaNormalizer.normalize_schema(schema)

      assert result["additionalProperties"] == false
    end

    test "adds additionalProperties: false to nested objects in properties" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "config" => %{
            "type" => "object",
            "properties" => %{"setting" => %{"type" => "string"}}
          }
        }
      }

      result = SchemaNormalizer.normalize_schema(schema)

      assert result["additionalProperties"] == false
      assert result["properties"]["config"]["additionalProperties"] == false
    end

    test "adds additionalProperties: false to objects in array items" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "items" => %{
            "type" => "array",
            "items" => %{
              "type" => "object",
              "properties" => %{"id" => %{"type" => "string"}}
            }
          }
        }
      }

      result = SchemaNormalizer.normalize_schema(schema)

      assert result["properties"]["items"]["items"]["additionalProperties"] == false
    end

    test "handles nil schema" do
      assert SchemaNormalizer.normalize_schema(nil) == nil
    end

    test "handles non-object schemas" do
      schema = %{"type" => "string"}

      result = SchemaNormalizer.normalize_schema(schema)

      assert result == schema
    end

    test "handles deeply nested structures" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "level1" => %{
            "type" => "object",
            "properties" => %{
              "level2" => %{
                "type" => "object",
                "properties" => %{
                  "level3" => %{"type" => "string"}
                }
              }
            }
          }
        }
      }

      result = SchemaNormalizer.normalize_schema(schema)

      assert result["additionalProperties"] == false
      assert result["properties"]["level1"]["additionalProperties"] == false
      assert result["properties"]["level1"]["properties"]["level2"]["additionalProperties"] == false
    end
  end

  describe "remove_unsupported_features/1" do
    test "removes oneOf from schema" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "result_type" => %{
            "oneOf" => [
              %{"type" => "string"},
              %{"type" => "object", "properties" => %{}}
            ]
          }
        }
      }

      result = SchemaNormalizer.remove_unsupported_features(schema)

      refute Map.has_key?(result["properties"]["result_type"], "oneOf")
    end

    test "removes anyOf from schema" do
      schema = %{
        "anyOf" => [%{"type" => "string"}, %{"type" => "number"}]
      }

      result = SchemaNormalizer.remove_unsupported_features(schema)

      refute Map.has_key?(result, "anyOf")
    end

    test "removes allOf from schema" do
      schema = %{
        "allOf" => [%{"type" => "object"}, %{"properties" => %{}}]
      }

      result = SchemaNormalizer.remove_unsupported_features(schema)

      refute Map.has_key?(result, "allOf")
    end

    test "handles nil schema" do
      assert SchemaNormalizer.remove_unsupported_features(nil) == nil
    end
  end

  describe "normalize_tool/1" do
    test "sets strict to false on tools" do
      function =
        LangChain.Function.new!(%{
          name: "tool1",
          description: "Test tool 1",
          parameters_schema: %{"type" => "object", "properties" => %{}},
          strict: true,
          function: fn _, _ -> {:ok, "result"} end
        })

      result = SchemaNormalizer.normalize_tool(function)

      assert result.strict == false
    end

    test "normalizes schema and removes unsupported features" do
      function =
        LangChain.Function.new!(%{
          name: "tool1",
          description: "Test tool 1",
          parameters_schema: %{
            "type" => "object",
            "properties" => %{
              "result_type" => %{
                "oneOf" => [%{"type" => "string"}]
              }
            }
          },
          function: fn _, _ -> {:ok, "result"} end
        })

      result = SchemaNormalizer.normalize_tool(function)

      assert result.parameters_schema["additionalProperties"] == false
      refute Map.has_key?(result.parameters_schema["properties"]["result_type"], "oneOf")
    end
  end

  describe "normalize_chain/1" do
    test "normalizes all tools in a chain" do
      function1 =
        LangChain.Function.new!(%{
          name: "tool1",
          description: "Test tool 1",
          parameters_schema: %{"type" => "object", "properties" => %{}},
          strict: true,
          function: fn _, _ -> {:ok, "result"} end
        })

      function2 =
        LangChain.Function.new!(%{
          name: "tool2",
          description: "Test tool 2",
          parameters_schema: %{"type" => "object", "properties" => %{}},
          strict: true,
          function: fn _, _ -> {:ok, "result"} end
        })

      chain = %LangChain.Chains.LLMChain{tools: [function1, function2]}

      result = SchemaNormalizer.normalize_chain(chain)

      assert Enum.all?(result.tools, fn tool ->
               tool.parameters_schema["additionalProperties"] == false and tool.strict == false
             end)
    end
  end
end
