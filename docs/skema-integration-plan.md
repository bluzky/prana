# Skema Integration Implementation Plan

## Overview

This document outlines the implementation plan for integrating Skema schema validation library into Prana's HTTP integration. Skema will provide robust input validation and schema introspection capabilities for workflow actions.

## Goals

- **Primary**: Add input validation to HTTP integration actions
- **Secondary**: Enable schema introspection for UI form generation
- **Tertiary**: Establish pattern for other integrations to follow

## Task Breakdown

### **Phase 1: Foundation Setup**

#### **skema-1: Add Skema Dependency** (HIGH PRIORITY)
- **File**: `mix.exs`
- **Action**: Add `{:skema, "~> 1.0"}` to dependencies
- **Command**: `mix deps.get`
- **Validation**: Verify Skema is available in IEx

#### **skema-4: Update Action Behavior** (HIGH PRIORITY)
- **File**: `lib/prana/behaviours/action.ex`
- **Changes**:
  ```elixir
  @doc """
  Returns the input schema for this action.
  Used for validation and UI generation.
  """
  @callback input_schema() :: module() | map()

  @doc """
  Validates input_map for this action using schema.
  """
  @callback validate_params(input_map :: map()) ::
    {:ok, validated_map :: map()} | {:error, reasons :: [String.t()]}

  @optional_callbacks [input_schema: 0, validate_input: 1]
  ```

### **Phase 2: Schema Definition**

#### **skema-2: Create RequestAction Schemas** (HIGH PRIORITY)
- **File**: `lib/prana/integrations/http.ex`
- **Implementation**:
  ```elixir
  defmodule Prana.Integrations.HTTP.RequestAction do
    use Skema

    defschema HTTPRequestSchema do
      field :url, :string, required: true,
            validation: [format: ~r/^https?:\/\/.+/]

      field :method, :string, default: "GET",
            inclusion: ["GET", "POST", "PUT", "DELETE", "HEAD", "PATCH", "OPTIONS"]

      field :headers, :map, default: %{}

      field :timeout, :integer, default: 5000,
            number: [greater_than: 0, less_than: 300_000]

      field :retry, :integer, default: 0,
            number: [greater_than_or_equal_to: 0, less_than: 10]

      field :auth, AuthSchema
      field :body, :string
      field :json, :map
      field :params, :map, default: %{}
    end

    defschema AuthSchema do
      field :type, :string, required: true,
            inclusion: ["basic", "bearer", "api_key"]

      field :username, :string  # For basic auth
      field :password, :string  # For basic auth
      field :token, :string     # For bearer auth
      field :key, :string       # For API key
      field :header, :string, default: "X-API-Key"  # For API key
    end
  end
  ```

#### **skema-3: Create WebhookAction Schemas** (HIGH PRIORITY)
- **File**: `lib/prana/integrations/http.ex`
- **Implementation**:
  ```elixir
  defmodule Prana.Integrations.HTTP.WebhookAction do
    use Skema

    defschema WebhookSchema do
      field :timeout_hours, :float, default: 24.0,
            number: [greater_than: 0.1, less_than_or_equal_to: 8760.0]

      field :base_url, :string,
            validation: [format: ~r/^https?:\/\/.+/]

      field :webhook_config, WebhookConfigSchema, default: %{}
    end

    defschema WebhookConfigSchema do
      field :path, :string, default: "/webhook"
      field :secret, :string
      field :headers, :map, default: %{}
    end
  end
  ```

### **Phase 3: Validation Implementation**

#### **skema-5: Implement RequestAction Validation** (HIGH PRIORITY)
- **File**: `lib/prana/integrations/http.ex`
- **Changes**:
  ```elixir
  @impl true
  def validate_params(input_map) do
    case Skema.cast_and_validate(input_map, HTTPRequestSchema) do
      {:ok, validated_data} -> {:ok, validated_data}
      {:error, errors} -> {:error, format_errors(errors)}
    end
  end

  defp format_errors(errors) do
    Enum.map(errors, fn {field, messages} ->
      "#{field}: #{Enum.join(messages, ", ")}"
    end)
  end
  ```

#### **skema-6: Implement WebhookAction Validation** (HIGH PRIORITY)
- **File**: `lib/prana/integrations/http.ex`
- **Changes**:
  ```elixir
  @impl true
  def validate_params(input_map) do
    case Skema.cast_and_validate(input_map, WebhookSchema) do
      {:ok, validated_data} -> {:ok, validated_data}
      {:error, errors} -> {:error, format_errors(errors)}
    end
  end
  ```

#### **skema-7: Add Schema Callback Implementation** (MEDIUM PRIORITY)
- **Files**: Both action modules
- **Implementation**:
  ```elixir
  # In RequestAction
  @impl true
  def input_schema, do: HTTPRequestSchema

  # In WebhookAction
  @impl true
  def input_schema, do: WebhookSchema
  ```

### **Phase 4: Utilities & Enhancement**

#### **skema-9: Schema Metadata Extraction** (MEDIUM PRIORITY)
- **File**: `lib/prana/schema_utils.ex` (new file)
- **Purpose**: Extract metadata from Skema schemas for UI generation
- **Implementation**:
  ```elixir
  defmodule Prana.SchemaUtils do
    def extract_field_info(schema_module) do
      # Introspect Skema schema and return field metadata
      # - Field types
      # - Required fields
      # - Default values
      # - Validation rules
      # - Nested schemas
    end

    def generate_form_config(schema_module) do
      # Convert schema to form configuration for UI
    end
  end
  ```

### **Phase 5: Testing**

#### **skema-10: Update HTTP Integration Tests** (HIGH PRIORITY)
- **File**: `test/prana/integrations/http_test.exs`
- **New Test Cases**:
  ```elixir
  describe "RequestAction schema validation" do
    test "validates required URL field"
    test "validates HTTP method inclusion"
    test "validates timeout range"
    test "validates URL format"
    test "validates auth configuration"
    test "casts string numbers to integers"
    test "applies default values"
    test "validates nested auth schema"
  end

  describe "WebhookAction schema validation" do
    test "validates timeout_hours range"
    test "validates base_url format"
    test "applies default webhook config"
  end
  ```

#### **skema-11: Schema Introspection Tests** (MEDIUM PRIORITY)
- **File**: `test/prana/schema_utils_test.exs` (new file)
- **Test Cases**:
  ```elixir
  describe "schema introspection" do
    test "extracts field information from RequestAction schema"
    test "extracts validation rules"
    test "handles nested schemas"
    test "generates form configuration"
  end
  ```

### **Phase 6: Documentation**

#### **skema-12: Update Documentation** (LOW PRIORITY)
- **Files**:
  - Update HTTP integration usage guide
  - Add schema examples to README
  - Document validation patterns
- **Content**:
  - Schema definition examples
  - Validation error handling
  - UI generation examples

## Implementation Strategy

### **1. Incremental Approach**
- Implement one action at a time
- Test thoroughly at each step
- Maintain backward compatibility

### **2. Error Handling**
- Convert Skema validation errors to user-friendly messages
- Provide detailed field-level error information
- Support both programmatic and UI error display

### **3. Schema Design Principles**
- **Declarative**: Clear, readable schema definitions
- **Comprehensive**: Cover all input scenarios
- **Flexible**: Support optional and conditional fields
- **Reusable**: Shared schemas for common patterns

### **4. Testing Strategy**
- **Unit tests**: Individual schema validation
- **Integration tests**: End-to-end workflow validation
- **Edge cases**: Invalid inputs, type coercion, nested validation

## Expected Benefits

### **Immediate**
- ✅ Robust input validation for HTTP actions
- ✅ Automatic type casting and default values
- ✅ Clear validation error messages
- ✅ Reduced boilerplate validation code

### **Long-term**
- 🎯 **UI Generation**: Frontend forms from schema introspection
- 🎯 **API Documentation**: Self-documenting action parameters
- 🎯 **Type Safety**: Validated and typed workflow data
- 🎯 **Pattern**: Template for other integrations

## Success Criteria

1. **Functional**: All HTTP action inputs validated through Skema
2. **Quality**: Comprehensive test coverage (>95%)
3. **Usability**: Clear error messages for invalid inputs
4. **Performance**: Validation overhead <10ms per action
5. **Maintainability**: Clean, readable schema definitions

## Risk Mitigation

### **Potential Risks**
- **Learning curve**: Team unfamiliarity with Skema
- **Schema complexity**: Conditional and nested validations
- **Performance**: Validation overhead in workflows
- **Breaking changes**: Impact on existing workflows

### **Mitigation Strategies**
- Start with simple schemas and iterate
- Comprehensive testing and documentation
- Performance benchmarking and optimization
- Gradual rollout with backward compatibility

## Timeline Estimate

- **Phase 1-3** (Core Implementation): 2-3 days
- **Phase 4** (Utilities): 1 day
- **Phase 5** (Testing): 1-2 days
- **Phase 6** (Documentation): 1 day

**Total Estimated Time**: 5-7 days

## Dependencies

- **External**: Skema library (~> 1.0)
- **Internal**: Prana.Behaviour.Action interface
- **Testing**: ExUnit test framework

## Notes

- Skip IntegrationRegistry schema introspection for now
- Focus on direct action schema access
- Prioritize validation over UI generation features
- Ensure all existing HTTP tests continue to pass
