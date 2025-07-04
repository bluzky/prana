defmodule Prana.SchemaUtilsTest do
  use ExUnit.Case, async: true
  
  alias Prana.SchemaUtils
  alias Prana.Integrations.HTTP.RequestAction
  alias Prana.Integrations.HTTP.WebhookAction

  describe "extract_field_info/1" do
    test "extracts field information from RequestAction schema" do
      field_info = SchemaUtils.extract_field_info(RequestAction.HTTPRequestSchema)
      
      assert is_map(field_info)
      assert Map.has_key?(field_info, :fields)
      assert Map.has_key?(field_info, :required_fields)
      assert Map.has_key?(field_info, :schema_module)
      
      # Check that URL field is present and required
      url_field = Enum.find(field_info.fields, &(&1.name == :url))
      assert url_field != nil
      assert url_field.required == true
      assert url_field.type == :string
      
      # Check that method field has default value
      method_field = Enum.find(field_info.fields, &(&1.name == :method))
      assert method_field != nil
      assert method_field.default == "GET"
      assert method_field.required == false
    end

    test "extracts validation rules" do
      field_info = SchemaUtils.extract_field_info(RequestAction.HTTPRequestSchema)
      
      # Find URL field and check its validation
      url_field = Enum.find(field_info.fields, &(&1.name == :url))
      assert Enum.any?(url_field.validation, fn {key, _} -> key == :format end)
      
      # Find method field and check inclusion validation
      method_field = Enum.find(field_info.fields, &(&1.name == :method))
      assert Enum.any?(method_field.validation, fn {key, _} -> key == :inclusion end)
    end

    test "handles nested schemas" do
      field_info = SchemaUtils.extract_field_info(RequestAction.HTTPRequestSchema)
      
      # Find auth field which should have nested schema
      auth_field = Enum.find(field_info.fields, &(&1.name == :auth))
      assert auth_field != nil
      assert auth_field.nested_schema == RequestAction.AuthSchema
    end
  end

  describe "generate_form_config/1" do
    test "generates form configuration from RequestAction schema" do
      form_config = SchemaUtils.generate_form_config(RequestAction.HTTPRequestSchema)
      
      assert is_map(form_config)
      assert Map.has_key?(form_config, :form_id)
      assert Map.has_key?(form_config, :fields)
      assert Map.has_key?(form_config, :schema_module)
      
      # Check form ID generation
      assert form_config.form_id =~ ~r/.*_form$/
      
      # Check field conversion
      url_field = Enum.find(form_config.fields, &(&1.name == "url"))
      assert url_field != nil
      assert url_field.type == "text"
      assert url_field.label == "Url"
      assert url_field.required == true
      assert url_field.placeholder == "https://example.com"
    end

    test "converts field types correctly" do
      form_config = SchemaUtils.generate_form_config(RequestAction.HTTPRequestSchema)
      
      # String field should become text input
      url_field = Enum.find(form_config.fields, &(&1.name == "url"))
      assert url_field.type == "text"
      
      # Integer field should become number input
      timeout_field = Enum.find(form_config.fields, &(&1.name == "timeout"))
      assert timeout_field.type == "number"
      
      # Map field should become object input
      headers_field = Enum.find(form_config.fields, &(&1.name == "headers"))
      assert headers_field.type == "object"
    end

    test "converts validation rules to form validation" do
      form_config = SchemaUtils.generate_form_config(RequestAction.HTTPRequestSchema)
      
      # URL field should have pattern validation
      url_field = Enum.find(form_config.fields, &(&1.name == "url"))
      assert Map.has_key?(url_field.validation, :pattern)
      assert Map.has_key?(url_field.validation, :required)
      
      # Method field should have enum validation
      method_field = Enum.find(form_config.fields, &(&1.name == "method"))
      assert Map.has_key?(method_field.validation, :enum)
      
      # Timeout field should have min/max validation
      timeout_field = Enum.find(form_config.fields, &(&1.name == "timeout"))
      assert Map.has_key?(timeout_field.validation, :min)
      assert Map.has_key?(timeout_field.validation, :max)
    end
  end

  describe "get_schema_metadata/1" do
    test "returns comprehensive schema metadata" do
      metadata = SchemaUtils.get_schema_metadata(RequestAction.HTTPRequestSchema)
      
      assert is_map(metadata)
      assert Map.has_key?(metadata, :schema_module)
      assert Map.has_key?(metadata, :schema_name)
      assert Map.has_key?(metadata, :fields)
      assert Map.has_key?(metadata, :field_count)
      assert Map.has_key?(metadata, :required_fields)
      assert Map.has_key?(metadata, :optional_fields)
      assert Map.has_key?(metadata, :nested_schemas)
      assert Map.has_key?(metadata, :validation_summary)
      
      # Check that we have the expected number of fields
      assert metadata.field_count > 0
      
      # Check that URL is in required fields
      assert :url in metadata.required_fields
      
      # Check that we have nested schemas (auth)
      assert RequestAction.AuthSchema in metadata.nested_schemas
    end

    test "summarizes validation rules" do
      metadata = SchemaUtils.get_schema_metadata(RequestAction.HTTPRequestSchema)
      
      validation_summary = metadata.validation_summary
      assert Map.has_key?(validation_summary, :has_required_fields)
      assert Map.has_key?(validation_summary, :has_format_validation)
      assert Map.has_key?(validation_summary, :has_inclusion_validation)
      assert Map.has_key?(validation_summary, :has_number_validation)
      
      # RequestAction schema should have all these validation types
      assert validation_summary.has_required_fields == true
      assert validation_summary.has_format_validation == true
      assert validation_summary.has_inclusion_validation == true
      assert validation_summary.has_number_validation == true
    end
  end

  describe "WebhookAction schema introspection" do
    test "extracts WebhookAction field information" do
      field_info = SchemaUtils.extract_field_info(WebhookAction.WebhookSchema)
      
      assert is_map(field_info)
      
      # Check timeout_hours field
      timeout_field = Enum.find(field_info.fields, &(&1.name == :timeout_hours))
      assert timeout_field != nil
      assert timeout_field.type == :float
      assert timeout_field.default == 24.0
      assert timeout_field.required == false
      
      # Check webhook_config nested schema
      webhook_config_field = Enum.find(field_info.fields, &(&1.name == :webhook_config))
      assert webhook_config_field != nil
      assert webhook_config_field.nested_schema == WebhookAction.WebhookConfigSchema
    end

    test "generates WebhookAction form configuration" do
      form_config = SchemaUtils.generate_form_config(WebhookAction.WebhookSchema)
      
      assert is_map(form_config)
      
      # Check timeout_hours field conversion
      timeout_field = Enum.find(form_config.fields, &(&1.name == "timeout_hours"))
      assert timeout_field != nil
      assert timeout_field.type == "number"
      assert timeout_field.label == "Timeout Hours"
      assert timeout_field.required == false
      assert timeout_field.default == 24.0
    end
  end

  describe "error handling" do
    test "handles invalid schema modules gracefully" do
      # Test with a module that doesn't have schema definition
      result = SchemaUtils.extract_field_info(String)
      assert {:error, reason} = result
      assert is_binary(reason)
    end
  end

  describe "utility functions" do
    test "extract_validation_rules/1 handles various validation types" do
      field_config = %{
        type: :string,
        required: true,
        validation: [
          format: ~r/^https?:\/\/.+/,
          inclusion: ["GET", "POST"]
        ]
      }
      
      rules = SchemaUtils.extract_validation_rules(field_config)
      
      assert {:type, :string} in rules
      assert {:required, true} in rules
      assert {:format, ~r/^https?:\/\/.+/} in rules
      assert {:inclusion, ["GET", "POST"]} in rules
    end

    test "extract_nested_schema/1 identifies nested schema modules" do
      # Test with nested schema
      field_config = %{type: RequestAction.AuthSchema}
      assert SchemaUtils.extract_nested_schema(field_config) == RequestAction.AuthSchema
      
      # Test with primitive type
      field_config = %{type: :string}
      assert SchemaUtils.extract_nested_schema(field_config) == nil
    end
  end
end