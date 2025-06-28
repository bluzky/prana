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
- **Description**: Multi-case routing based on expression evaluation
- **Input Ports**: `["input"]`
- **Output Ports**: `["premium", "standard", "basic", "default"]`

**Input Parameters**:
- `switch_expression`: Expression to evaluate (e.g., `"user_type"`)
- `cases`: Map of case_value => {port_name, output_data}
- `default_data`: Data for default case

**Returns**:
- `{:ok, data, port_name}` for matching case
- `{:ok, default_data, "default"}` for no match

**Example**:
```elixir
%{
  "switch_expression" => "user_type",
  "cases" => %{
    "premium" => {"premium", %{"discount" => 0.2}},
    "standard" => {"standard", %{"discount" => 0.1}},
    "basic" => {"basic", %{"discount" => 0.0}}
  },
  "default_data" => %{"discount" => 0.0}
}
```

### Data Integration

**Purpose**: Data manipulation and combination operations
**Category**: Core
**Module**: `Prana.Integrations.Data`

The Data integration provides essential data manipulation capabilities for combining and processing data from multiple workflow paths.

#### Actions

##### Merge
- **Action Name**: `merge`
- **Description**: Combine data from multiple input sources
- **Input Ports**: `["input"]`
- **Output Ports**: `["success", "error"]`

**Input Parameters**:
- `strategy`: Merge strategy (`"combine_objects"` | `"combine_arrays"` | `"last_wins"`)
- `inputs`: List of data to merge

**Merge Strategies**:

1. **combine_objects** (default): Merges maps using `Map.merge/2`, later maps override earlier ones
2. **combine_arrays**: Filters to arrays and flattens them with `List.flatten/1`
3. **last_wins**: Returns the last item from inputs list

**Returns**:
- `{:ok, merged_data, "success"}` on successful merge
- `{:error, reason, "error"}` if merge fails

**Examples**:

*Combine Objects*:
```elixir
%{
  "strategy" => "combine_objects",
  "inputs" => [
    %{"name" => "John", "age" => 30},
    %{"city" => "NYC", "age" => 31}
  ]
}
# Result: %{"name" => "John", "age" => 31, "city" => "NYC"}
```

*Combine Arrays*:
```elixir
%{
  "strategy" => "combine_arrays",
  "inputs" => [
    [1, 2, 3],
    [4, 5],
    %{"ignored" => "non-array"}
  ]
}
# Result: [1, 2, 3, 4, 5]
```

*Last Wins*:
```elixir
%{
  "strategy" => "last_wins",
  "inputs" => [
    %{"first" => true},
    %{"second" => true},
    %{"third" => true}
  ]
}
# Result: %{"third" => true}
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
      from_node_id: "age_check",
      from_port: "true",
      to_node_id: "adult_processor"
    },
    # Connect condition false branch to minor processing  
    %Connection{
      from_node_id: "age_check",
      from_port: "false", 
      to_node_id: "minor_processor"
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
    "switch_expression" => "subscription_tier",
    "cases" => %{
      "premium" => {"premium", %{"features" => ["all"]}},
      "standard" => {"standard", %{"features" => ["basic", "advanced"]}},
      "basic" => {"basic", %{"features" => ["basic"]}}
    },
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
          output_ports: ["success", "error"]
        }
      }
    }
  end

  def my_action(input_map) do
    # Implementation
    {:ok, result, "success"}
  end
end
```

Register the integration with:
```elixir
Prana.IntegrationRegistry.register_integration(MyApp.CustomIntegration)
```