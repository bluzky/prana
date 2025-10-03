# Data Integration

**Purpose**: Data manipulation and combination operations  
**Category**: Core  
**Module**: `Prana.Integrations.Data`

The Data integration provides essential data manipulation capabilities for combining and processing data from multiple workflow paths.

## Actions

### Merge
- **Action Name**: `merge`
- **Description**: Combine data from multiple named input ports (diamond pattern coordination)
- **Input Ports**: `["input_a", "input_b"]`
- **Output Ports**: `["main"]`

**Input Parameters**:
- `strategy`: Merge strategy (`"append"` | `"merge"` | `"concat"`) - defaults to `"append"`
- `input_a`: Data from first input port
- `input_b`: Data from second input port

**Merge Strategies (ADR-002)**:

1. **append** (default): Collect all inputs as separate array elements `[input_a, input_b]`
2. **merge**: Combine object inputs using `Map.merge/2`, ignores non-maps
3. **concat**: Flatten and concatenate array inputs using `List.flatten/1`, ignores non-arrays

**Returns**:
- `{:ok, merged_data}` on successful merge
- `{:error, reason}` if merge fails

**Examples**:

*Append Strategy (Default)*:
```elixir
%{
  "strategy" => "append",
  "input_a" => %{"name" => "John", "age" => 30},
  "input_b" => %{"city" => "NYC", "status" => "active"}
}
# Result: [%{"name" => "John", "age" => 30}, %{"city" => "NYC", "status" => "active"}]
```

*Merge Strategy*:
```elixir
%{
  "strategy" => "merge",
  "input_a" => %{"name" => "John", "age" => 30},
  "input_b" => %{"city" => "NYC", "age" => 31}
}
# Result: %{"name" => "John", "age" => 31, "city" => "NYC"}
```

*Concat Strategy*:
```elixir
%{
  "strategy" => "concat",
  "input_a" => [1, 2, 3],
  "input_b" => [4, 5]
}
# Result: [1, 2, 3, 4, 5]
```

### Set Data
- **Action Name**: `set_data`
- **Description**: Create or transform data using templates in manual or json mode
- **Input Ports**: `["main"]`
- **Output Ports**: `["main"]`

**Input Parameters**:
- `mode`: Operating mode (`"manual"` | `"json"`) - defaults to `"manual"`
- `mapping_map`: Map used in manual mode (optional)
- `json_template`: JSON template string used in json mode (optional)

**Operating Modes**:

1. **manual** (default): Simple key-value mapping with template-rendered values
2. **json**: Complex nested data structures from JSON template strings

**Returns**:
- `{:ok, data}` on successful data creation
- `{:ok, nil}` when required parameter is missing
- `{:error, reason}` if processing fails

**Examples**:

*Manual Mode (Default)*:
```elixir
# Node params with templates (rendered by NodeExecutor):
%{
  "mode" => "manual",
  "mapping_map" => %{
    "user_id" => 123,                    # Rendered from "{{ $input.id }}"
    "full_name" => "John Doe",           # Rendered from "{{ $input.first_name }} {{ $input.last_name }}"
    "status" => "processed"
  }
}
# Result: %{"user_id" => 123, "full_name" => "John Doe", "status" => "processed"}
```

*JSON Mode*:
```elixir
# Node params with JSON template (rendered by NodeExecutor):
%{
  "mode" => "json",
  "json_template" => ~s|{"user":{"id":456,"name":"JANE DOE"},"orders":[{"order_id":"ord_1","amount":99.99}]}|
}
# Result: %{"user" => %{"id" => 456, "name" => "JANE DOE"}, "orders" => [%{"order_id" => "ord_1", "amount" => 99.99}]}
```

*Missing Parameters*:
```elixir
%{"mode" => "manual"}  # mapping_map missing
# Result: {:ok, nil}

%{"mode" => "json"}    # json_template missing  
# Result: {:ok, nil}
```

**Template Integration**:
The NodeExecutor automatically renders all templates in the node's `params` before calling the action. This means:
- Template expressions like `"{{ $input.field }}"` are resolved before the action executes
- The action receives already-processed data and focuses on data transformation logic
- In manual mode, `mapping_map` values are already rendered
- In json mode, `json_template` is already rendered and ready for JSON parsing