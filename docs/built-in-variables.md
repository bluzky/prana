# Built-in Variables Reference

This document provides a comprehensive reference for all built-in variables available in the Prana expression engine and action context.

## Overview

Prana provides several built-in variables that can be accessed within expressions and actions. These variables provide access to input data, node outputs, environment configuration, and execution metadata.

## Primary Built-in Variables

### `$input` - Node Input Data

Access data passed to the current node via input ports.

```elixir
# Simple field access
"$input.email"
"$input.user_id"

# Nested field access
"$input.user.profile.name"

# Array access
"$input.users[0].name"
"$input.items[1].price"

# Wildcard extraction (returns arrays)
"$input.users.*.name"
"$input.products.*.price"

# Filtering (returns arrays)
"$input.users.{role: \"admin\"}.email"
"$input.orders.{status: \"completed\", total: 100}"
```

**Structure**: `%{"port_name" => data}` for multi-port input routing

### `$nodes` - Completed Node Outputs

Access outputs from previously completed nodes in the workflow.

```elixir
# Access node output
"$nodes.api_call.response.user_id"
"$nodes.validation.status"

# Nested access
"$nodes.database_query.results[0].name"
"$nodes.external_api.data.*.id"

# Multiple node coordination
"$nodes.user_service.user_id"
"$nodes.payment_service.transaction_id"
```

**Structure**: `%{node_id => output_data}`

### `$env` - Environment Variables

Access environment-specific configuration data provided by the application.

```elixir
# API credentials
"$env.api_key"
"$env.database_url"

# Configuration values
"$env.timeout"
"$env.max_retries"

# Feature flags
"$env.feature_enabled"
```

**Structure**: `%{variable_name => value}`

### `$vars` - Workflow Variables

Access workflow-level variables defined in the workflow definition.

```elixir
# Configuration
"$vars.api_url"
"$vars.timeout"

# Business logic parameters
"$vars.discount_rate"
"$vars.max_attempts"

# Dynamic configuration
"$vars.processing_mode"
```

**Structure**: `%{variable_name => value}`

**Note**: Documentation may reference `$variables`, but the implementation uses `$vars`.

### `$workflow` - Workflow Metadata

Access workflow identification and metadata.

```elixir
# Workflow identification
"$workflow.id"
"$workflow.version"

# Usage in conditional logic
"$workflow.id" == "user_onboarding_v2"
```

**Structure**: 
```elixir
%{
  "id" => String.t(),      # Workflow identifier
  "version" => integer()   # Workflow version
}
```

### `$execution` - Execution Metadata

Access execution-specific metadata and preparation data.

```elixir
# Execution tracking
"$execution.id"
"$execution.mode"

# Preparation data
"$execution.preparation.prepared_at"
"$execution.preparation.context"
```

**Structure**:
```elixir
%{
  "id" => String.t(),           # Execution identifier
  "mode" => atom(),             # Execution mode (:sync, :async, :fire_and_forget)
  "preparation" => map()        # Preparation data from middleware
}
```

## Expression Engine Features

All built-in variables support these advanced expression features:

### Simple Field Access
```elixir
"$input.email"                    # Single value
"$nodes.api_call.response.user_id" # Nested access
"$vars.api_url"                   # Variables
```

### Array Access
```elixir
"$input.users[0].name"            # Index access
"$nodes.search_results.items[1]"  # Node output arrays
```

### Wildcard Extraction (Returns Arrays)
```elixir
"$input.users.*.name"             # All user names
"$nodes.batch_process.results.*"  # All batch results
"$vars.configs.*.endpoint"        # All configuration endpoints
```

### Filtering (Returns Arrays)
```elixir
"$input.users.{role: \"admin\"}.email"        # Filter by role
"$nodes.validation.results.{status: \"pass\"}" # Filter node outputs
"$vars.services.{enabled: true}.url"          # Filter enabled services
```

## Complete Context Example

Here's a complete example of the expression context structure:

```elixir
%{
  "$input" => %{
    "email" => "user@example.com",
    "age" => 25,
    "preferences" => %{"theme" => "dark", "notifications" => true}
  },
  "$nodes" => %{
    "api_call" => %{
      "response" => %{"user_id" => 123, "status" => "success"}
    },
    "validation" => %{
      "valid" => true,
      "score" => 95,
      "errors" => []
    }
  },
  "$env" => %{
    "api_key" => "secret123",
    "database_url" => "postgres://localhost:5432/mydb",
    "feature_flags" => %{"new_ui" => true}
  },
  "$vars" => %{
    "api_url" => "https://api.example.com",
    "timeout" => 30000,
    "retry_count" => 3,
    "processing_config" => %{"batch_size" => 100}
  },
  "$workflow" => %{
    "id" => "user_onboarding_v2",
    "version" => 1
  },
  "$execution" => %{
    "id" => "exec_abc123",
    "mode" => :async,
    "preparation" => %{
      "prepared_at" => "2025-01-01T00:00:00Z",
      "context" => %{"source" => "web_app"}
    }
  }
}
```

## Usage in Actions

Actions receive these variables through the expression context when their input configuration is processed:

```elixir
# In action configuration
%Prana.Node{
  id: "send_notification",
  integration: "email",
  action: "send_message",
  input_config: %{
    "to" => "$input.email",
    "subject" => "Welcome to #{$workflow.id}",
    "body" => "Hello #{$input.name}, your account ID is #{$nodes.registration.user_id}"
  }
}
```

## Usage in Conditions

Built-in variables can be used in conditional expressions:

```elixir
# In connection conditions
%Prana.Connection{
  condition: "$nodes.validation.score >= 90",
  # ...
}

# In Logic integration conditions
%Prana.Node{
  integration: "logic",
  action: "if_condition",
  input_config: %{
    "condition" => "$env.feature_enabled && $input.user_tier == \"premium\""
  }
}
```

## Implementation Notes

### Variable Name Discrepancy
- **Documentation**: Often references `$variables`
- **Implementation**: Uses `$vars`
- **Recommendation**: Use `$vars` in actual expressions

### Runtime State Variables
These internal variables are available in the `execution.__runtime` map but are not directly exposed:

- **`"nodes"`**: Node execution results (accessed via `$nodes`)
- **`"env"`**: Environment data (accessed via `$env`)
- **`"active_paths"`**: Conditional branching state
- **`"executed_nodes"`**: Execution order tracking

### Performance Considerations
- Node outputs are cached with O(1) lookup performance
- Expression evaluation is optimized for nested field access
- Wildcard and filtering operations may have performance implications on large datasets

## Related Documentation

- [Expression Engine](expression_engine.md) - Detailed expression syntax and evaluation
- [Building Workflows](guides/building_workflows.md) - Using variables in workflow composition
- [Writing Integrations](guides/writing_integrations.md) - Accessing variables in custom actions
- [Built-in Integrations](built-in-integrations.md) - Variable usage in built-in actions