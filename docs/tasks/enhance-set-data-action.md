
# Task: Enhance `set_data` Action

**Date:** 2025-07-27
**Status:** ✅ Completed

## 1. Background

The existing `data.set_data` action is a simple pass-through node that outputs its parameters. This is insufficient for real-world workflows that require dynamic data construction and transformation. The goal is to evolve this action into a powerful and flexible tool for data manipulation, similar to the "Set" or "Transform" nodes in platforms like n8n.

## 2. Proposed Solution

The `set_data` action will be enhanced to support two distinct operating modes, selectable via a `mode` parameter. This provides both a simple interface for basic key-value mapping and a powerful templating system for complex, nested data structures.

### 2.1. Action Parameters

The action's `params` will be structured as follows:

- `mode` (string, optional): The operating mode.
  - `"manual"` (default): For simple, one-level key-value mapping.
  - `"json"`: For creating complex, nested data structures from a JSON template.
- `mapping_map` (map, optional): A map used in `manual` mode. Each value is a template string that will be rendered.
- `json_template` (string, optional): A string containing a JSON structure, used in `json` mode. The entire string is rendered as a template.

### 2.2. Example Usage

#### Manual Mode

This mode is for creating or modifying a flat map.

**Params:**
```json
{
  "mode": "manual",
  "mapping_map": {
    "user_id": "{{ $input.id }}",
    "full_name": "{{ $input.first_name | capitalize }} {{ $input.last_name | capitalize }}",
    "status": "processed"
  }
}
```

**Output:**
```json
{
  "user_id": 123,
  "full_name": "John Doe",
  "status": "processed"
}
```

#### JSON Mode

This mode is for creating complex, nested JSON objects or arrays.

**Params:**
```json
{
  "mode": "json",
  "json_template": "{ \"user\": { \"id\": {{ $input.user.id }}, \"name\": \"{{ $input.user.name | upper_case }}\" }, \"orders\": [ {%- for order in $input.orders -%} { \"order_id\": \"{{ order.id }}\", \"amount\": {{ order.amount }} } {%- if not loop.last -%},{%- endif -%} {%- endfor -%} ] }"
}
```

**Output:**
```json
{
  "user": {
    "id": 456,
    "name": "JANE DOE"
  },
  "orders": [
    {
      "order_id": "ord_1",
      "amount": 99.99
    },
    {
      "order_id": "ord_2",
      "amount": 12.50
    }
  ]
}
```

## 3. Implementation Plan

### Step 1: Dependency Management

1.  **Inspect `mix.lock`**: Check for an existing JSON parsing library (e.g., `jason`, `poison`).
2.  **Add Dependency (if needed)**: If no suitable library exists, add `{:jason, "~> 1.4"}` to `mix.exs` after user confirmation and run `mix deps.get`.

### Step 2: Update Action Logic (`lib/prana/integrations/data/set_data_action.ex`)

1.  **Update Specification**: Modify the `description` in `specification/0` to reflect the new dual-mode functionality.
2.  **Rewrite `execute/2`**:
    - Read the `mode` from `params`, defaulting to `"manual"`.
    - Implement a `case` statement to handle the `mode`.
    - **`"manual"` mode**:
        - Get `mapping_map` from `params`.
        - If it's a map, iterate through its values and render each one using `Prana.Template.render/2`.
        - Return the new map with rendered values.
    - **`"json"` mode**:
        - Get `json_template` from `params`.
        - If it's a string, render it using `Prana.Template.render/2`.
        - Parse the resulting string with `Jason.decode/1`.
        - Return the parsed map or list.
    - **Error Handling**: Implement robust error handling for missing parameters, template rendering failures, and JSON parsing errors. Return structured error tuples.

### Step 3: Unit Testing (`test/prana/integrations/data/set_data_action_test.exs`)

1.  **Create Test File**: Create the test file if it doesn't exist.
2.  **Write Test Cases**:
    - **Manual Mode**:
        - Test successful key-value mapping.
        - Test behavior with a missing or empty `mapping_map`.
        - Test a template rendering error in one of the values.
    - **JSON Mode**:
        - Test successful rendering and parsing of a complex JSON object.
        - Test successful rendering and parsing of a JSON array.
        - Test for a missing `json_template` parameter.
        - Test for a template rendering error.
        - Test for a JSON parsing error (i.e., the rendered string is not valid JSON).
    - **General**:
        - Test that the action defaults to `manual` mode when `mode` is not provided.
        - Test that an invalid `mode` value returns an error.

## 4. Acceptance Criteria

- The `set_data` action correctly implements both `manual` and `json` modes.
- The action handles missing or invalid parameters gracefully for each mode.
- Template rendering and JSON parsing errors are caught and returned as structured error messages.
- All unit tests pass, covering the scenarios outlined above.
- The `mix.exs` file is updated with the `jason` dependency if it was not already present.
