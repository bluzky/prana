# Logic Integration

**Purpose**: Conditional branching and control flow operations  
**Category**: Core  
**Module**: `Prana.Integrations.Logic`

The Logic integration provides conditional routing capabilities for workflow execution, enabling IF/ELSE branching and multi-case switch routing.

## Actions

### IF Condition
- **Action Name**: `if_condition`
- **Description**: Evaluate a condition and route to true or false branch
- **Input Ports**: `["main"]`
- **Output Ports**: `["true", "false"]`

**Input Parameters**:
- `condition`: Expression to evaluate (e.g., `"$input.age >= 18"`, `"true"`, `"false"`)

**Returns**:
- `{:ok, %{}, "true"}` if condition is true
- `{:ok, %{}, "false"}` if condition is false
- `{:error, reason}` if evaluation fails

**Condition Evaluation**:
- String expressions like `"$input.should_retry"` are evaluated against the input context
- Boolean values are used directly
- Truthy values (non-null, non-empty) evaluate to true
- Falsy values (null, empty string, "false") evaluate to false

**Example**:
```elixir
%{
  "condition" => "$input.should_retry"
}
# If input context contains %{"should_retry" => true}, routes to "true" port
# If input context contains %{"should_retry" => false}, routes to "false" port
```

### Switch
- **Action Name**: `switch`
- **Description**: Multi-case routing based on simple condition expressions
- **Input Ports**: `["main"]`
- **Output Ports**: `["*"]` (Dynamic - supports any port name)

**Input Parameters**:
- `cases`: Array of condition objects for routing logic

**Case Object Properties**:
- `condition`: Expression to evaluate (truthy/falsy check)
- `port`: Output port name (can be any custom name, defaults to "default")

**Returns**:
- `{:ok, nil, port_name}` for matching case
- `{:error, reason}` if no case matches

**Example**:
```elixir
%{
  "cases" => [
    %{"condition" => "$input.tier == \"premium\"", "port" => "premium_port"},
    %{"condition" => "$input.verified == true", "port" => "verified_port"},
    %{"condition" => "$input.status == \"active\"", "port" => "active_port"},
    %{"condition" => true, "port" => "default_port"}
  ]
}
```

**Condition Evaluation**:
- Cases are evaluated in order
- First case with a truthy condition (non-null, non-empty) matches
- If no case matches, action returns an error

**Dynamic Port Names**: The switch action supports any custom port name (e.g., `"premium_port"`, `"verified_user"`, `"special_case"`). This allows for semantic, meaningful port names instead of generic numbered outputs.

**Note**: The current implementation performs a simple truthy check on the condition field. More sophisticated expression evaluation may be added in future versions.