# Built-in Integrations

Prana includes several core integrations that provide essential workflow functionality. These integrations are built into the system and available by default.

## Core Integrations

### Logic Integration

**Purpose**: Conditional branching and control flow operations
**Category**: Core
**Module**: `Prana.Integrations.Logic`

The Logic integration provides conditional routing capabilities for workflow execution, enabling IF/ELSE branching and multi-case switch routing.

#### Actions

##### IF Condition
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

##### Switch
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

### Data Integration

**Purpose**: Data manipulation and combination operations
**Category**: Core
**Module**: `Prana.Integrations.Data`

The Data integration provides essential data manipulation capabilities for combining and processing data from multiple workflow paths.

#### Actions

##### Merge
- **Action Name**: `merge`
- **Description**: Combine data from multiple named input ports (diamond pattern coordination)
- **Input Ports**: `["input_a", "input_b"]`
- **Output Ports**: `["success", "error"]`

**Input Parameters**:
- `strategy`: Merge strategy (`"append"` | `"merge"` | `"concat"`) - defaults to `"append"`
- `input_a`: Data from first input port
- `input_b`: Data from second input port

**Merge Strategies (ADR-002)**:

1. **append** (default): Collect all inputs as separate array elements `[input_a, input_b]`
2. **merge**: Combine object inputs using `Map.merge/2`, ignores non-maps
3. **concat**: Flatten and concatenate array inputs using `List.flatten/1`, ignores non-arrays

**Returns**:
- `{:ok, merged_data, "success"}` on successful merge
- `{:error, reason, "error"}` if merge fails

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

### Manual Integration

**Purpose**: Testing and development utilities
**Category**: Test
**Module**: `Prana.Integrations.Manual`

The Manual integration provides simple test actions for workflow development and testing scenarios.

#### Actions

##### Trigger
- **Action Name**: `trigger`
- **Description**: Simple trigger for testing workflows
- **Input Ports**: `[]`
- **Output Ports**: `["success"]`

##### Process Adult
- **Action Name**: `process_adult`
- **Description**: Process adult data (test action)
- **Input Ports**: `["input"]`
- **Output Ports**: `["success"]`

##### Process Minor
- **Action Name**: `process_minor`
- **Description**: Process minor data (test action)
- **Input Ports**: `["input"]`
- **Output Ports**: `["success"]`

## Usage in Workflows

### Conditional Branching Example

```elixir
# Diamond pattern: trigger → condition → (adult_path OR minor_path) → merge
workflow = %Workflow{
  nodes: [
    %Node{
      id: "age_check",
      integration_name: "logic",
      action_name: "if_condition",
      input_map: %{"condition" => "age >= 18"}
    },
    %Node{
      id: "merge_results",
      integration_name: "data", 
      action_name: "merge",
      input_map: %{"strategy" => "combine_objects"}
    }
  ],
  connections: [
    # Connect condition true branch to adult processing
    %Connection{
      from: "age_check",
      from_port: "true",
      to: "adult_processor"
    },
    # Connect condition false branch to minor processing  
    %Connection{
      from: "age_check",
      from_port: "false", 
      to: "minor_processor"
    }
  ]
}
```

### Switch Routing Example

```elixir
%Node{
  id: "user_router",
  integration_name: "logic",
  action_name: "switch",
  input_map: %{
    "cases" => [
      %{"condition" => "$input.subscription_tier", "value" => "premium", "port" => "premium_users", "data" => %{"features" => ["all"]}},
      %{"condition" => "$input.subscription_tier", "value" => "standard", "port" => "standard_users", "data" => %{"features" => ["basic", "advanced"]}},
      %{"condition" => "$input.subscription_tier", "value" => "basic", "port" => "basic_users", "data" => %{"features" => ["basic"]}}
    ],
    "default_port" => "trial_users",
    "default_data" => %{"features" => ["trial"]}
  }
}
```

## Integration Development

To create custom integrations, implement the `Prana.Behaviour.Integration` behavior:

```elixir
defmodule MyApp.CustomIntegration do
  @behaviour Prana.Behaviour.Integration

  def definition do
    %Prana.Integration{
      name: "custom",
      display_name: "Custom Integration",
      description: "Custom workflow actions",
      version: "1.0.0",
      category: "custom",
      actions: %{
        "my_action" => %Prana.Action{
          name: "my_action",
          module: __MODULE__,
          function: :my_action,
          input_ports: ["input"],
          output_ports: ["success", "error"]  # Fixed ports
        },
        "dynamic_action" => %Prana.Action{
          name: "dynamic_action", 
          module: __MODULE__,
          function: :dynamic_action,
          input_ports: ["input"],
          output_ports: ["*"]  # Dynamic ports - any port name allowed
        }
      }
    }
  end

  def my_action(input_map) do
    # Implementation with fixed ports
    {:ok, result, "success"}
  end
  
  def dynamic_action(input_map) do
    # Implementation with custom port names
    port_name = determine_custom_port(input_map)
    {:ok, result, port_name}
  end
end
```

### Dynamic Output Ports

Actions can support dynamic output ports by using `["*"]` as the `output_ports` value. This allows the action to return any custom port name at runtime:

**Benefits**:
- **Semantic port names**: Use meaningful names like `"premium_users"` instead of `"output_1"`
- **Flexible routing**: Support any number of output scenarios
- **Self-documenting workflows**: Port names indicate their purpose

**Usage**:
- Set `output_ports: ["*"]` in action definition
- Return `{:ok, data, "custom_port_name"}` from action function
- Any port name will pass validation

Register the integration with:
```elixir
Prana.IntegrationRegistry.register_integration(MyApp.CustomIntegration)
```