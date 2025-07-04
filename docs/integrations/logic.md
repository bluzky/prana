# Logic Integration

**Purpose**: Conditional branching and control flow operations  
**Category**: Core  
**Module**: `Prana.Integrations.Logic`

The Logic integration provides conditional routing capabilities for workflow execution, enabling IF/ELSE branching and multi-case switch routing.

## Actions

### IF Condition
- **Action Name**: `if_condition`
- **Description**: Evaluate a condition and route to true or false branch
- **Input Ports**: `["input"]`
- **Output Ports**: `["true", "false"]`

**Input Parameters**:
- `condition`: Expression to evaluate (e.g., `"age >= 18"`, `"true"`, `"false"`)
- `true_data`: Optional data to pass on true branch (defaults to input)
- `false_data`: Optional data to pass on false branch (defaults to input)

**Returns**:
- `{:ok, data, "true"}` if condition is true
- `{:ok, data, "false"}` if condition is false
- `{:error, reason, "false"}` if evaluation fails

**Example**:
```elixir
%{
  "condition" => "age >= 18",
  "true_data" => %{"status" => "adult"},
  "false_data" => %{"status" => "minor"}
}
```

### Switch
- **Action Name**: `switch`
- **Description**: Multi-case routing based on simple condition expressions
- **Input Ports**: `["input"]`
- **Output Ports**: `["*"]` (Dynamic - supports any port name)

**Input Parameters**:
- `cases`: Array of condition objects for routing logic
- `default_port`: Default port name (optional, defaults to `"default"`)
- `default_data`: Optional default data (defaults to input_map)

**Case Object Properties**:
- `condition`: Expression to evaluate (e.g., `"$input.field"`)
- `value`: Expected value to match against
- `port`: Output port name (can be any custom name)
- `data`: Optional output data (defaults to input_map)

**Returns**:
- `{:ok, data, port_name}` for matching case
- `{:ok, default_data, default_port}` for no match

**Example**:
```elixir
%{
  "cases" => [
    %{"condition" => "$input.tier", "value" => "premium", "port" => "premium_port"},
    %{"condition" => "$input.verified", "value" => true, "port" => "verified_port"},
    %{"condition" => "$input.status", "value" => "active", "port" => "active_port", "data" => %{"priority" => "high"}}
  ],
  "default_port" => "default",
  "default_data" => %{"message" => "no match"}
}
```

**Dynamic Port Names**: The switch action supports any custom port name (e.g., `"premium_port"`, `"verified_user"`, `"special_case"`). This allows for semantic, meaningful port names instead of generic numbered outputs.