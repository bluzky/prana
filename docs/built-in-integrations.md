# Built-in Integrations

Prana includes several core integrations that provide essential workflow functionality. These integrations are built into the system and available by default.

## Core Integrations

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
- **Usage**: Entry point for test workflows
- **Returns**: Passes through input data unchanged

##### Process Adult
- **Action Name**: `process_adult`
- **Description**: Process adult data with timestamp
- **Input Ports**: `["input"]`
- **Output Ports**: `["success"]`
- **Returns**: Input data with `processed_as: "adult"` and timestamp

**Example**:
```elixir
# Input: %{"user_id" => 123, "age" => 25}
# Output: %{"user_id" => 123, "age" => 25, "processed_as" => "adult", "timestamp" => DateTime.utc_now()}
```

##### Process Minor
- **Action Name**: `process_minor`
- **Description**: Process minor data with timestamp
- **Input Ports**: `["input"]`
- **Output Ports**: `["success"]`
- **Returns**: Input data with `processed_as: "minor"` and timestamp

**Example**:
```elixir
# Input: %{"user_id" => 456, "age" => 16}
# Output: %{"user_id" => 456, "age" => 16, "processed_as" => "minor", "timestamp" => DateTime.utc_now()}
```

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

### Workflow Integration

**Purpose**: Sub-workflow orchestration and coordination
**Category**: Coordination
**Module**: `Prana.Integrations.Workflow`

The Workflow integration provides sub-workflow execution capabilities with suspension/resume patterns for parent-child workflow coordination.

#### Actions

##### Execute Workflow
- **Action Name**: `execute_workflow`
- **Description**: Execute a sub-workflow with synchronous or asynchronous coordination
- **Input Ports**: `["input"]`
- **Output Ports**: `["success", "error", "timeout"]`

**Input Parameters**:
- `workflow_id`: The ID of the sub-workflow to execute (required)
- `input_data`: Data to pass to the sub-workflow (optional, defaults to full input)
- `execution_mode`: Execution mode - `"sync"` | `"async"` | `"fire_and_forget"` (optional, defaults to `"sync"`)
- `timeout_ms`: Maximum time to wait for sub-workflow completion in milliseconds (optional, defaults to 5 minutes)
- `failure_strategy`: How to handle sub-workflow failures - `"fail_parent"` | `"continue"` (optional, defaults to `"fail_parent"`)

**Execution Modes**:

1. **Synchronous (`"sync"`)** - Default
   - Parent workflow suspends until sub-workflow completes
   - Returns: `{:suspend, :sub_workflow_sync, suspend_data}`

2. **Asynchronous (`"async"`)**
   - Parent workflow suspends, sub-workflow executes async
   - Parent resumes when sub-workflow completes
   - Returns: `{:suspend, :sub_workflow_async, suspend_data}`

3. **Fire-and-Forget (`"fire_and_forget"`)**
   - Parent workflow triggers sub-workflow and continues immediately
   - Returns: `{:suspend, :sub_workflow_fire_forget, suspend_data}`

**Examples**:

*Synchronous Sub-workflow*:
```elixir
%{
  "workflow_id" => "user_verification",
  "input_data" => %{"user_id" => 123, "document_type" => "passport"},
  "execution_mode" => "sync",
  "timeout_ms" => 600_000  # 10 minutes
}
```

*Fire-and-Forget Notification*:
```elixir
%{
  "workflow_id" => "send_welcome_email",
  "input_data" => %{"user_email" => "user@example.com"},
  "execution_mode" => "fire_and_forget"
}
```

## Creating Custom Integrations

For information on creating custom integrations, see the [Writing Integrations Guide](guides/writing_integrations.md).