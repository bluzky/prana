defmodule Prana.SchemaUtils do
  @moduledoc """
  Utilities for extracting metadata from Skema schemas for UI generation and introspection.

  This module provides functions to extract field information, validation rules,
  and generate form configurations from Skema schema modules.
  """

  @doc """
  Extract field information from a Skema schema module.

  Returns a map containing field metadata including:
  - Field types
  - Required fields
  - Default values
  - Validation rules
  - Nested schemas

  ## Examples

      iex> Prana.SchemaUtils.extract_field_info(MySchema)
      %{
        fields: [
          %{
            name: :url,
            type: :string,
            required: true,
            default: nil,
            validation: [format: ~r/^https?:\/\/.+/]
          },
          %{
            name: :method,
            type: :string,
            required: false,
            default: "GET",
            validation: [inclusion: ["GET", "POST", "PUT", "DELETE"]]
          }
        ]
      }
  """
  def extract_field_info(schema_module) do
    # Access the schema definition through Skema's introspection
    schema_definition = schema_module.__schema__()

    fields =
      Enum.map(schema_definition.fields, fn {field_name, field_config} ->
        %{
          name: field_name,
          type: field_config.type,
          required: field_config.required || false,
          default: field_config.default,
          validation: extract_validation_rules(field_config),
          nested_schema: extract_nested_schema(field_config)
        }
      end)

    %{
      schema_module: schema_module,
      fields: fields,
      required_fields: fields |> Enum.filter(& &1.required) |> Enum.map(& &1.name)
    }
  rescue
    error ->
      {:error, "Failed to extract field info: #{inspect(error)}"}
  end

  @doc """
  Generate form configuration from a Skema schema module.

  Returns a form configuration suitable for UI generation, including
  field types, validation rules, and display information.

  ## Examples

      iex> Prana.SchemaUtils.generate_form_config(MySchema)
      %{
        form_id: "my_schema_form",
        fields: [
          %{
            name: "url",
            type: "text",
            label: "URL",
            required: true,
            placeholder: "https://example.com",
            validation: %{
              required: true,
              pattern: "^https?:\/\/.+"
            }
          }
        ]
      }
  """
  def generate_form_config(schema_module) do
    case extract_field_info(schema_module) do
      %{fields: fields} ->
        form_fields = Enum.map(fields, &convert_field_to_form_config/1)

        %{
          form_id: generate_form_id(schema_module),
          schema_module: schema_module,
          fields: form_fields
        }

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Extract validation rules from a field configuration.

  Returns a list of validation rules that can be used for both
  server-side validation and client-side UI generation.
  """
  def extract_validation_rules(field_config) do
    rules = []

    # Add type-specific validation
    rules = if Map.get(field_config, :type), do: [{:type, field_config.type} | rules], else: rules

    # Add required validation
    rules = if Map.get(field_config, :required), do: [{:required, true} | rules], else: rules

    # Add format validation
    rules = if Map.get(field_config, :format), do: [{:format, field_config.format} | rules], else: rules

    # Add inclusion validation
    rules = if Map.get(field_config, :in), do: [{:inclusion, field_config.in} | rules], else: rules

    # Add number validation
    rules = if Map.get(field_config, :number), do: [{:number, field_config.number} | rules], else: rules

    rules
  end

  @doc """
  Check if a field has a nested schema.

  Returns the nested schema module if present, nil otherwise.
  """
  def extract_nested_schema(field_config) do
    case Map.get(field_config, :type) do
      module when is_atom(module) ->
        # Check if this is a nested schema module
        if function_exported?(module, :__schema__, 0) do
          module
        end

      _ ->
        nil
    end
  end

  @doc """
  Get schema metadata including validation rules and field types.

  Returns comprehensive metadata about a schema that can be used
  for documentation, validation, and UI generation.
  """
  def get_schema_metadata(schema_module) do
    case extract_field_info(schema_module) do
      %{fields: fields} = info ->
        %{
          schema_module: schema_module,
          schema_name: get_schema_name(schema_module),
          fields: fields,
          field_count: length(fields),
          required_fields: info.required_fields,
          optional_fields: fields |> Enum.filter(&(!&1.required)) |> Enum.map(& &1.name),
          nested_schemas: fields |> Enum.filter(& &1.nested_schema) |> Enum.map(& &1.nested_schema),
          validation_summary: summarize_validation_rules(fields)
        }

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private helper functions

  defp convert_field_to_form_config(field) do
    %{
      name: to_string(field.name),
      type: map_field_type_to_form_type(field.type),
      label: humanize_field_name(field.name),
      required: field.required,
      default: field.default,
      placeholder: generate_placeholder(field),
      validation: convert_validation_to_form_rules(field.validation)
    }
  end

  defp map_field_type_to_form_type(:string), do: "text"
  defp map_field_type_to_form_type(:integer), do: "number"
  defp map_field_type_to_form_type(:float), do: "number"
  defp map_field_type_to_form_type(:boolean), do: "checkbox"
  defp map_field_type_to_form_type(:map), do: "object"
  defp map_field_type_to_form_type(_), do: "text"

  defp humanize_field_name(field_name) do
    field_name |> to_string() |> String.replace("_", " ") |> String.split() |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp generate_placeholder(field) do
    case field.name do
      :url -> "https://example.com"
      :method -> "GET"
      :timeout -> "5000"
      :email -> "user@example.com"
      _ -> nil
    end
  end

  defp convert_validation_to_form_rules(validation_rules) do
    Enum.reduce(validation_rules, %{}, fn
      {:required, true}, acc -> Map.put(acc, :required, true)
      {:format, regex}, acc -> Map.put(acc, :pattern, Regex.source(regex))
      {:inclusion, values}, acc -> Map.put(acc, :enum, values)
      {:number, opts}, acc -> Map.merge(acc, convert_number_validation(opts))
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  defp convert_number_validation(opts) do
    Enum.reduce(opts, %{}, fn
      {:greater_than, value}, acc -> Map.put(acc, :min, value + 1)
      {:greater_than_or_equal_to, value}, acc -> Map.put(acc, :min, value)
      {:less_than, value}, acc -> Map.put(acc, :max, value - 1)
      {:less_than_or_equal_to, value}, acc -> Map.put(acc, :max, value)
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  defp generate_form_id(schema_module) do
    schema_module
    |> to_string()
    |> String.split(".")
    |> List.last()
    |> String.downcase()
    |> Kernel.<>("_form")
  end

  defp get_schema_name(schema_module) do
    schema_module
    |> to_string()
    |> String.split(".")
    |> List.last()
  end

  defp summarize_validation_rules(fields) do
    %{
      has_required_fields: Enum.any?(fields, & &1.required),
      has_format_validation:
        Enum.any?(fields, fn field ->
          Enum.any?(field.validation, fn {key, _} -> key == :format end)
        end),
      has_inclusion_validation:
        Enum.any?(fields, fn field ->
          Enum.any?(field.validation, fn {key, _} -> key == :inclusion end)
        end),
      has_number_validation:
        Enum.any?(fields, fn field ->
          Enum.any?(field.validation, fn {key, _} -> key == :number end)
        end)
    }
  end
end
