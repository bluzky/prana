# Data Serialization and Deserialization Guide

This guide covers how to serialize and deserialize Prana's core data structures for persistence, API transport, and inter-service communication.

## Overview

Prana provides built-in serialization support for all core data structures, enabling seamless conversion between Elixir structs and JSON-compatible maps with proper type handling and nested structure conversion.

## Core Serialization API

All core structs implement a consistent serialization API:

- **`from_map/1`** - Deserializes maps (with string keys) to typed structs
- **`to_map/1`** - Serializes structs to maps for JSON/storage

### Supported Data Structures

- `Prana.Workflow` - Complete workflows with nodes and connections
- `Prana.Node` - Individual workflow nodes  
- `Prana.Connection` - Port-based node connections
- `Prana.WorkflowExecution` - Execution instances with runtime state
- `Prana.NodeExecution` - Individual node execution records

## Workflow Serialization

### Basic Usage

```elixir
# Create a workflow
workflow = %Prana.Workflow{
  id: "user_registration",
  name: "User Registration Flow",
  description: "Handle new user registration",
  version: 1,
  nodes: [
    %Prana.Node{
      key: "validate_email",
      name: "Validate Email",
      type: "manual.validate",
      params: %{"field" => "email", "required" => true}
    },
    %Prana.Node{
      key: "create_user",
      name: "Create User Account", 
      type: "manual.create",
      params: %{"table" => "users"}
    }
  ],
  connections: %{
    "validate_email" => %{
      "success" => [
        %Prana.Connection{
          from: "validate_email",
          from_port: "success", 
          to: "create_user",
          to_port: "input"
        }
      ]
    }
  },
  variables: %{"environment" => "production"}
}

# Serialize to JSON-compatible map
workflow_map = Prana.Workflow.to_map(workflow)
json_string = Jason.encode!(workflow_map)

# Store to database/file...
File.write!("workflow.json", json_string)

# Later: Load and deserialize
json_data = File.read!("workflow.json")
workflow_map = Jason.decode!(json_data)
restored_workflow = Prana.Workflow.from_map(workflow_map)

# All data preserved including nested structures
restored_workflow.id == "user_registration"  # true
restored_workflow.nodes |> length() == 2     # true
```

### Advanced Workflow Features

The serialization handles all workflow complexity automatically:

```elixir
# Complex workflows with multiple ports and connections
complex_workflow = %Prana.Workflow{
  id: "payment_processing",
  name: "Payment Processing Workflow",
  connections: %{
    "payment_gateway" => %{
      "success" => [
        %Prana.Connection{from: "payment_gateway", from_port: "success", to: "send_receipt", to_port: "input"}
      ],
      "failed" => [
        %Prana.Connection{from: "payment_gateway", from_port: "failed", to: "retry_payment", to_port: "input"}
      ],
      "timeout" => [
        %Prana.Connection{from: "payment_gateway", from_port: "timeout", to: "log_error", to_port: "input"}
      ]
    }
  }
}

# Serialization preserves all connection structures
workflow_map = Prana.Workflow.to_map(complex_workflow)
# workflow_map["connections"]["payment_gateway"]["success"][0]["from"] == "payment_gateway"
```

## Workflow Execution Serialization

### Runtime State Preservation

```elixir
# Create execution with runtime state
execution = %Prana.WorkflowExecution{
  id: "exec_123",
  workflow_id: "user_registration", 
  status: :running,
  trigger_type: "webhook",
  trigger_data: %{"user_email" => "user@example.com"},
  vars: %{"user_id" => "user_456"},
  node_executions: %{
    "validate_email" => [
      %Prana.NodeExecution{
        node_key: "validate_email",
        status: :completed,
        execution_index: 0,
        run_index: 0,
        output_data: %{"email_valid" => true},
        output_port: "success"
      }
    ]
  },
  suspended_node_id: "create_user",
  suspension_type: "webhook",
  suspension_data: %{"webhook_url" => "https://api.example.com/webhook/123"},
  metadata: %{"attempt_count" => 1}
}

# Serialize execution (includes nested NodeExecutions)
execution_map = Prana.WorkflowExecution.to_map(execution)

# Store to database
MyApp.Repo.insert!(%ExecutionRecord{
  id: execution.id,
  data: execution_map,
  status: execution.status
})

# Later: Load and restore
record = MyApp.Repo.get!(ExecutionRecord, "exec_123")
restored_execution = Prana.WorkflowExecution.from_map(record.data)

# Runtime state can be rebuilt
env_data = %{"api_key" => "secret", "base_url" => "https://api.example.com"}
ready_execution = Prana.WorkflowExecution.rebuild_runtime(restored_execution, env_data)
```

### Suspension and Resume Cycles

```elixir
# Execution suspended waiting for webhook
suspended_execution = %Prana.WorkflowExecution{
  id: "exec_suspended",
  status: :suspended,
  suspended_node_id: "webhook_wait",
  suspension_type: "webhook", 
  suspension_data: %{
    "webhook_url" => "https://app.com/webhook/abc123",
    "webhook_id" => "wh_456",
    "timeout_seconds" => 3600
  },
  suspended_at: ~U[2024-01-01 14:30:00Z]
}

# Serialize and store
execution_map = Prana.WorkflowExecution.to_map(suspended_execution)
# Store with indexed webhook_id for fast lookup...

# Later: Webhook arrives, deserialize and resume
execution_data = lookup_execution_by_webhook("wh_456")
execution = Prana.WorkflowExecution.from_map(execution_data)

# Resume execution
resumed_execution = execution
|> Prana.WorkflowExecution.resume_suspension()
|> Map.put(:status, :running)
```

## Type Handling

The serialization system automatically handles type conversions:

### Automatic Type Conversions

```elixir
# DateTime fields
execution_map = %{
  "id" => "exec_123",
  "workflow_id" => "wf_456", 
  "started_at" => "2024-01-01T10:00:00Z",     # String
  "completed_at" => "2024-01-01T10:05:00Z"    # String
}

execution = Prana.WorkflowExecution.from_map(execution_map)
execution.started_at   # ~U[2024-01-01 10:00:00Z] (DateTime)
execution.completed_at # ~U[2024-01-01 10:05:00Z] (DateTime)

# Status atoms
node_exec_map = %{
  "node_key" => "api_call",
  "status" => "completed"  # String
}

node_exec = Prana.NodeExecution.from_map(node_exec_map)
node_exec.status  # :completed (atom)

# Execution modes
execution_map = %{
  "id" => "exec_123",
  "workflow_id" => "wf_456",
  "execution_mode" => "sync"  # String
}

execution = Prana.WorkflowExecution.from_map(execution_map)
execution.execution_mode  # :sync (atom)
```

### Complex Nested Structures

```elixir
# Node parameters with nested data
node_map = %{
  "key" => "data_transform",
  "name" => "Transform User Data",
  "type" => "data.transform",
  "params" => %{
    "mappings" => [
      %{"from" => "input.user.email", "to" => "user_email"},
      %{"from" => "input.user.profile.name", "to" => "full_name"}
    ],
    "filters" => %{
      "status" => "active",
      "roles" => ["admin", "user"]
    },
    "options" => %{
      "strict_mode" => true,
      "default_value" => nil
    }
  }
}

node = Prana.Node.from_map(node_map)
# All nested structure preserved with proper types
node.params["mappings"] |> length()  # 2
node.params["filters"]["roles"]      # ["admin", "user"]
```



## Error Handling

The serialization system provides clear error messages for invalid data:

```elixir
# Missing required fields
Prana.Workflow.from_map(%{})
# ** (MatchError) no match of right hand side value: {:error, %{errors: %{id: ["can't be blank"], name: ["can't be blank"]}}}

# Invalid data types  
Prana.NodeExecution.from_map(%{"node_key" => "test", "status" => "invalid_status"})
# ** (MatchError) no match of right hand side value: {:error, %{errors: %{status: ["is invalid"]}}}
```

Always wrap deserialization in proper error handling for production code.