# Manual Integration

**Purpose**: Testing and development utilities  
**Category**: Test  
**Module**: `Prana.Integrations.Manual`

The Manual integration provides simple test actions for workflow development and testing scenarios.

## Actions

### Trigger
- **Action Name**: `trigger`
- **Description**: Simple trigger for testing workflows
- **Input Ports**: `[]`
- **Output Ports**: `["success"]`
- **Usage**: Entry point for test workflows
- **Returns**: Passes through input data unchanged

### Process Adult
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

### Process Minor
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