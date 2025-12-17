defmodule Citadel.AI.SchemaNormalizer do
  @moduledoc """
  Normalizes JSON schemas for Anthropic API compatibility.

  Anthropic's API has specific requirements for tool schemas:
  - `additionalProperties: false` must be set on all object types
  - When using `strict: true`, only basic JSON schema types are supported
    (object, array, string, integer, number, boolean, null, enum, required)
  - `oneOf`, `anyOf`, `allOf` are NOT supported in strict mode

  This module normalizes schemas by:
  1. Adding `additionalProperties: false` to all object types
  2. Removing unsupported schema features (oneOf, anyOf, allOf)
  3. Setting `strict: false` on tools that have complex schemas
  """

  @doc """
  Normalizes a LangChain chain by updating all tool schemas.
  """
  def normalize_chain(chain) do
    normalized_tools = Enum.map(chain.tools, &normalize_tool/1)
    %{chain | tools: normalized_tools}
  end

  @doc """
  Normalizes a single LangChain.Function tool's parameter schema.

  Sets `strict: false` because AshAi generates schemas with features
  not supported by Anthropic's strict mode (like oneOf for result_type).
  """
  def normalize_tool(%LangChain.Function{} = function) do
    normalized_schema =
      function.parameters_schema
      |> normalize_schema()
      |> remove_unsupported_features()

    %{function | parameters_schema: normalized_schema, strict: false}
  end

  def normalize_tool(other), do: other

  @doc """
  Recursively normalizes a JSON schema to add `additionalProperties: false`
  to all object types.
  """
  def normalize_schema(nil), do: nil

  def normalize_schema(%{"type" => "object"} = schema) do
    schema
    |> Map.put("additionalProperties", false)
    |> normalize_nested_schemas()
  end

  def normalize_schema(schema) when is_map(schema) do
    normalize_nested_schemas(schema)
  end

  def normalize_schema(schema), do: schema

  defp normalize_nested_schemas(schema) when is_map(schema) do
    schema
    |> maybe_normalize_properties()
    |> maybe_normalize_items()
  end

  defp maybe_normalize_properties(%{"properties" => properties} = schema)
       when is_map(properties) do
    normalized = Map.new(properties, fn {key, value} -> {key, normalize_schema(value)} end)
    Map.put(schema, "properties", normalized)
  end

  defp maybe_normalize_properties(schema), do: schema

  defp maybe_normalize_items(%{"items" => items} = schema) when is_map(items) do
    Map.put(schema, "items", normalize_schema(items))
  end

  defp maybe_normalize_items(schema), do: schema

  @doc """
  Removes schema features not supported by Anthropic's strict mode.

  Unsupported features: oneOf, anyOf, allOf, $ref, definitions
  """
  def remove_unsupported_features(nil), do: nil

  def remove_unsupported_features(schema) when is_map(schema) do
    schema
    |> remove_unsupported_from_map()
    |> remove_unsupported_from_properties()
    |> remove_unsupported_from_items()
  end

  def remove_unsupported_features(schema), do: schema

  defp remove_unsupported_from_map(schema) do
    Map.drop(schema, ["oneOf", "anyOf", "allOf", "$ref", "definitions"])
  end

  defp remove_unsupported_from_properties(%{"properties" => properties} = schema)
       when is_map(properties) do
    cleaned = Map.new(properties, fn {key, value} -> {key, remove_unsupported_features(value)} end)
    Map.put(schema, "properties", cleaned)
  end

  defp remove_unsupported_from_properties(schema), do: schema

  defp remove_unsupported_from_items(%{"items" => items} = schema) when is_map(items) do
    Map.put(schema, "items", remove_unsupported_features(items))
  end

  defp remove_unsupported_from_items(schema), do: schema
end
