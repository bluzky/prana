# Workflow Integration

**Purpose**: Sub-workflow orchestration and coordination  
**Category**: Coordination  
**Module**: `Prana.Integrations.Workflow`

The Workflow integration provides sub-workflow execution capabilities with suspension/resume patterns for parent-child workflow coordination.

## Actions

### Execute Workflow
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
   - Returns: `{:suspend, :sub_workflow_sync, suspension_data}`

2. **Asynchronous (`"async"`)**
   - Parent workflow suspends, sub-workflow executes async
   - Parent resumes when sub-workflow completes
   - Returns: `{:suspend, :sub_workflow_async, suspension_data}`

3. **Fire-and-Forget (`"fire_and_forget"`)**
   - Parent workflow triggers sub-workflow and continues immediately
   - Returns: `{:suspend, :sub_workflow_fire_forget, suspension_data}`

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