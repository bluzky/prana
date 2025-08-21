# Building Workflows Guide

This guide explains how to compose workflows using Prana's built-in integrations and actions. Learn to create complex workflow patterns by combining nodes, connections, and data flow.

## ⚡ Connection Structure (Performance Optimized)

Prana uses a **double-indexed connection structure** for ultra-fast execution:

```elixir
connections: %{
  "source_node" => %{
    "output_port" => [%Connection{...}],
    "error_port" => [%Connection{...}]
  }
}
```

**Benefits**:
- **O(1) connection lookups** instead of O(n) scans
- **Ultra-fast routing** during workflow execution
- **Scalable performance** for large workflows
- **Direct port access** for conditional branching

## Workflow Structure

A workflow consists of:
- **Nodes**: Individual actions that perform work
- **Connections**: Data flow between nodes via ports
- **Input Data**: Initial data passed to the workflow
- **Variables**: Shared data accessible across the workflow

### Basic Workflow Template

```elixir
%Workflow{
  id: "workflow_id",
  name: "Workflow Name",
  nodes: [
    # List of nodes
  ],
  connections: %{
    # Double-indexed connections for O(1) lookups
    "source_node" => %{
      "output_port" => [%Connection{...}],
      "error_port" => [%Connection{...}]
    }
  },
  variables: %{
    # Optional shared variables
  }
}
```

## Core Building Patterns

### Linear Flow

Simple sequential execution where each node processes the output of the previous node.

```elixir
%Workflow{
  id: "user_onboarding",
  name: "User Onboarding Flow",
  nodes: [
    %Node{
      id: "start",
      custom_id: "start",
      type: :trigger,
      integration_name: "manual",
      action_name: "trigger"
    },
    %Node{
      id: "process_user",
      custom_id: "process_user",
      type: :action,
      integration_name: "manual",
      action_name: "process_adult",
      params: "$input"
    },
    %Node{
      id: "send_welcome",
      custom_id: "send_welcome",
      type: :action,
      integration_name: "workflow",
      action_name: "execute_workflow",
      params: %{
        "workflow_id" => "welcome_email",
        "input_data" => "$nodes.process_user",
        "execution_mode" => "fire_and_forget"
      }
    }
  ],
  connections: %{
    "start" => %{
      "success" => [
        %Connection{
          from: "start",
          to: "process_user",
          from_port: "success",
          to_port: "input"
        }
      ]
    },
    "process_user" => %{
      "success" => [
        %Connection{
          from: "process_user",
          to: "send_welcome",
          from_port: "success",
          to_port: "input"
        }
      ]
    }
  }
}
```

### Conditional Branching (IF/ELSE)

Route data to different paths based on conditions using the Logic integration.

```elixir
%Workflow{
  id: "age_verification",
  name: "Age-based Processing",
  nodes: [
    %Node{
      id: "trigger",
      custom_id: "trigger",
      type: :trigger,
      integration_name: "manual",
      action_name: "trigger"
    },
    %Node{
      id: "age_check",
      custom_id: "age_check",
      type: :action,
      integration_name: "logic",
      action_name: "if_condition",
      params: %{
        "condition" => "age >= 18",
        "age" => "$input.age"
      }
    },
    %Node{
      id: "process_adult",
      custom_id: "process_adult",
      type: :action,
      integration_name: "manual",
      action_name: "process_adult",
      params: "$input"
    },
    %Node{
      id: "process_minor",
      custom_id: "process_minor",
      type: :action,
      integration_name: "manual",
      action_name: "process_minor",
      params: "$input"
    }
  ],
  connections: [
    %Connection{
      from: "trigger",
      to: "age_check",
      from_port: "success",
      to_port: "input"
    },
    %Connection{
      from: "age_check",
      to: "process_adult",
      from_port: "true",
      to_port: "input"
    },
    %Connection{
      from: "age_check",
      to: "process_minor",
      from_port: "false",
      to_port: "input"
    }
  ]
}
```

### Multi-Path Routing (Switch)

Route to multiple different paths based on field values using switch logic.

```elixir
%Workflow{
  id: "subscription_routing",
  name: "Route by Subscription Tier",
  nodes: [
    %Node{
      id: "trigger",
      custom_id: "trigger",
      type: :trigger,
      integration_name: "manual",
      action_name: "trigger"
    },
    %Node{
      id: "tier_router",
      custom_id: "tier_router",
      type: :action,
      integration_name: "logic",
      action_name: "switch",
      params: %{
        "cases" => [
          %{
            "condition" => "$input.subscription_tier",
            "value" => "premium",
            "port" => "premium_flow",
            "data" => %{"features" => ["all"], "priority" => "high"}
          },
          %{
            "condition" => "$input.subscription_tier",
            "value" => "standard",
            "port" => "standard_flow",
            "data" => %{"features" => ["basic", "advanced"], "priority" => "medium"}
          },
          %{
            "condition" => "$input.subscription_tier",
            "value" => "basic",
            "port" => "basic_flow",
            "data" => %{"features" => ["basic"], "priority" => "low"}
          }
        ],
        "default_port" => "trial_flow",
        "default_data" => %{"features" => ["trial"], "priority" => "lowest"}
      }
    },
    %Node{
      id: "premium_processor",
      custom_id: "premium_processor",
      type: :action,
      integration_name: "manual",
      action_name: "process_adult",
      params: "$input"
    },
    %Node{
      id: "standard_processor",
      custom_id: "standard_processor",
      type: :action,
      integration_name: "manual",
      action_name: "process_adult",
      params: "$input"
    },
    %Node{
      id: "basic_processor",
      custom_id: "basic_processor",
      type: :action,
      integration_name: "manual",
      action_name: "process_minor",
      params: "$input"
    }
  ],
  connections: [
    %Connection{
      from: "trigger",
      to: "tier_router",
      from_port: "success",
      to_port: "input"
    },
    %Connection{
      from: "tier_router",
      to: "premium_processor",
      from_port: "premium_flow",
      to_port: "input"
    },
    %Connection{
      from: "tier_router",
      to: "standard_processor",
      from_port: "standard_flow",
      to_port: "input"
    },
    %Connection{
      from: "tier_router",
      to: "basic_processor",
      from_port: "basic_flow",
      to_port: "input"
    }
  ]
}
```

### Diamond Pattern (Fork-Join)

Split execution into parallel paths and merge results back together.

```elixir
%Workflow{
  id: "parallel_processing",
  name: "Fork-Join Pattern",
  nodes: [
    %Node{
      id: "start",
      custom_id: "start",
      type: :trigger,
      integration_name: "manual",
      action_name: "trigger"
    },
    %Node{
      id: "validation_path",
      custom_id: "validation_path",
      type: :action,
      integration_name: "manual",
      action_name: "process_adult",
      params: "$input"
    },
    %Node{
      id: "enrichment_path",
      custom_id: "enrichment_path",
      type: :action,
      integration_name: "manual",
      action_name: "process_minor",
      params: "$input"
    },
    %Node{
      id: "merge_results",
      custom_id: "merge_results",
      type: :action,
      integration_name: "data",
      action_name: "merge",
      params: %{
        "strategy" => "merge",
        "input_a" => "$nodes.validation_path",
        "input_b" => "$nodes.enrichment_path"
      }
    }
  ],
  connections: [
    # Fork: start connects to both parallel paths
    %Connection{
      from: "start",
      to: "validation_path",
      from_port: "success",
      to_port: "input"
    },
    %Connection{
      from: "start",
      to: "enrichment_path",
      from_port: "success",
      to_port: "input"
    },
    # Join: both paths connect to merge node
    %Connection{
      from: "validation_path",
      to: "merge_results",
      from_port: "success",
      to_port: "input_a"
    },
    %Connection{
      from: "enrichment_path",
      to: "merge_results",
      from_port: "success",
      to_port: "input_b"
    }
  ]
}
```

### Sub-workflow Orchestration

Coordinate parent and child workflows for complex business processes.

```elixir
%Workflow{
  id: "identity_verification",
  name: "Complete Identity Verification",
  nodes: [
    %Node{
      id: "start",
      custom_id: "start",
      type: :trigger,
      integration_name: "manual",
      action_name: "trigger"
    },
    %Node{
      id: "document_verification",
      custom_id: "document_verification",
      type: :action,
      integration_name: "workflow",
      action_name: "execute_workflow",
      params: %{
        "workflow_id" => "document_check",
        "input_data" => %{
          "user_id" => "$input.user_id",
          "document_type" => "$input.document_type",
          "document_image" => "$input.document_image"
        },
        "execution_mode" => "sync",
        "timeout_ms" => 300_000  # 5 minutes
      }
    },
    %Node{
      id: "biometric_verification",
      custom_id: "biometric_verification",
      type: :action,
      integration_name: "workflow",
      action_name: "execute_workflow",
      params: %{
        "workflow_id" => "biometric_check",
        "input_data" => %{
          "user_id" => "$input.user_id",
          "selfie_image" => "$input.selfie_image",
          "reference_image" => "$nodes.document_verification.extracted_photo"
        },
        "execution_mode" => "sync",
        "timeout_ms" => 180_000  # 3 minutes
      }
    },
    %Node{
      id: "send_notification",
      custom_id: "send_notification",
      type: :action,
      integration_name: "workflow",
      action_name: "execute_workflow",
      params: %{
        "workflow_id" => "verification_complete_notification",
        "input_data" => %{
          "user_email" => "$input.email",
          "verification_status" => "$nodes.biometric_verification.status"
        },
        "execution_mode" => "fire_and_forget"
      }
    }
  ],
  connections: [
    %Connection{
      from: "start",
      to: "document_verification",
      from_port: "success",
      to_port: "input"
    },
    %Connection{
      from: "document_verification",
      to: "biometric_verification",
      from_port: "success",
      to_port: "input"
    },
    %Connection{
      from: "biometric_verification",
      to: "send_notification",
      from_port: "success",
      to_port: "input"
    }
  ]
}
```

## Expression System

Use expressions to access and transform data throughout the workflow.

### Basic Field Access

```elixir
# Access input data
"$input.user_id"           # Gets user_id from workflow input
"$input.profile.name"      # Nested field access

# Access node results
"$nodes.validation.status" # Gets status from validation node output
"$nodes.api_call.response.data" # Nested access to node results

# Access variables
"$variables.api_url"       # Gets api_url from workflow variables
"$variables.config.timeout" # Nested variable access
```

### Array and Mixed Key Access

```elixir
# Array access
"$input.users[0].name"     # First user's name
"$input.scores[2]"         # Third score

# Mixed key access (NEW)
"$input[:atom_key]"        # Atom key access
"$input[\"string_key\"]"   # String key access
"$input.user[:name]"       # Dot notation + atom key
"$input.data[0].title"     # Array index + field access
"$input[\"config\"][:timeout]" # Mixed string and atom keys

# String vs integer keys
"$input.object[\"0\"]"     # String key "0"
"$input.object[0]"         # Integer key 0
```

### Expression Examples in Workflows

```elixir
%Node{
  id: "process_user",
  custom_id: "process_user",
  type: :action,
  integration_name: "manual",
  action_name: "process_adult",
  params: %{
    # Simple field mapping
    "user_id" => "$input.user_id",
    "email" => "$input.contact.email",

    # Using previous node results
    "validation_result" => "$nodes.validate_input.status",
    "enriched_data" => "$nodes.enrich_profile.user_data",

    # Using variables
    "api_endpoint" => "$variables.service_config.user_api",

    # Array and mixed key access
    "first_user_name" => "$input.users[0].name",
    "atom_field" => "$input[:atom_key]",
    "first_order_total" => "$input.orders[0].total"
  }
}
```

## Data Merging Strategies

The Data integration provides three merging strategies for combining results from parallel paths.

### Append Strategy (Default)

Collects inputs as separate array elements.

```elixir
%Node{
  id: "collect_results",
  custom_id: "collect_results",
  type: :action,
  integration_name: "data",
  action_name: "merge",
  params: %{
    "strategy" => "append",
    "input_a" => "$nodes.path_a.result",
    "input_b" => "$nodes.path_b.result"
  }
}

# Input A: %{"validation" => "passed", "score" => 85}
# Input B: %{"enrichment" => "completed", "tags" => ["premium"]}
# Result: [%{"validation" => "passed", "score" => 85}, %{"enrichment" => "completed", "tags" => ["premium"]}]
```

### Merge Strategy

Combines map inputs using deep merge.

```elixir
%Node{
  id: "combine_data",
  custom_id: "combine_data",
  type: :action,
  integration_name: "data",
  action_name: "merge",
  params: %{
    "strategy" => "merge",
    "input_a" => "$nodes.validation.user_data",
    "input_b" => "$nodes.enrichment.additional_data"
  }
}

# Input A: %{"name" => "John", "age" => 30, "email" => "john@example.com"}
# Input B: %{"city" => "NYC", "verified" => true, "age" => 31}
# Result: %{"name" => "John", "age" => 31, "email" => "john@example.com", "city" => "NYC", "verified" => true}
```

### Concat Strategy

Flattens and concatenates array inputs.

```elixir
%Node{
  id: "combine_lists",
  custom_id: "combine_lists",
  type: :action,
  integration_name: "data",
  action_name: "merge",
  params: %{
    "strategy" => "concat",
    "input_a" => "$nodes.source_a.items",
    "input_b" => "$nodes.source_b.items"
  }
}

# Input A: [1, 2, 3]
# Input B: [4, 5, 6]
# Result: [1, 2, 3, 4, 5, 6]
```

## Advanced Patterns

### Conditional Merge

Combine conditional logic with data merging.

```elixir
%Workflow{
  id: "conditional_merge",
  name: "Age-based Processing with Merge",
  nodes: [
    %Node{
      id: "trigger",
      custom_id: "trigger",
      type: :trigger,
      integration_name: "manual",
      action_name: "trigger"
    },
    %Node{
      id: "age_check",
      custom_id: "age_check",
      type: :action,
      integration_name: "logic",
      action_name: "if_condition",
      params: %{
        "condition" => "age >= 18",
        "age" => "$input.age"
      }
    },
    %Node{
      id: "adult_processing",
      custom_id: "adult_processing",
      type: :action,
      integration_name: "manual",
      action_name: "process_adult",
      params: "$input"
    },
    %Node{
      id: "minor_processing",
      custom_id: "minor_processing",
      type: :action,
      integration_name: "manual",
      action_name: "process_minor",
      params: "$input"
    },
    %Node{
      id: "merge_results",
      custom_id: "merge_results",
      type: :action,
      integration_name: "data",
      action_name: "merge",
      params: %{
        "strategy" => "append",
        "input_a" => "$nodes.adult_processing",
        "input_b" => "$nodes.minor_processing"
      }
    }
  ],
  connections: [
    %Connection{from: "trigger", to: "age_check", from_port: "success", to_port: "input"},
    %Connection{from: "age_check", to: "adult_processing", from_port: "true", to_port: "input"},
    %Connection{from: "age_check", to: "minor_processing", from_port: "false", to_port: "input"},
    %Connection{from: "adult_processing", to: "merge_results", from_port: "success", to_port: "input_a"},
    %Connection{from: "minor_processing", to: "merge_results", from_port: "success", to_port: "input_b"}
  ]
}
```

### Multi-level Sub-workflows

Coordinate multiple levels of sub-workflow execution.

```elixir
%Workflow{
  id: "complex_orchestration",
  name: "Multi-level Workflow Orchestration",
  nodes: [
    %Node{
      id: "trigger",
      custom_id: "trigger",
      type: :trigger,
      integration_name: "manual",
      action_name: "trigger"
    },
    %Node{
      id: "level1_validation",
      custom_id: "level1_validation",
      type: :action,
      integration_name: "workflow",
      action_name: "execute_workflow",
      params: %{
        "workflow_id" => "basic_validation",
        "input_data" => "$input",
        "execution_mode" => "sync"
      }
    },
    %Node{
      id: "level2_processing",
      custom_id: "level2_processing",
      type: :action,
      integration_name: "workflow",
      action_name: "execute_workflow",
      params: %{
        "workflow_id" => "advanced_processing",
        "input_data" => %{
          "original_input" => "$input",
          "validation_result" => "$nodes.level1_validation"
        },
        "execution_mode" => "sync",
        "timeout_ms" => 600_000
      }
    },
    %Node{
      id: "async_notifications",
      custom_id: "async_notifications",
      type: :action,
      integration_name: "workflow",
      action_name: "execute_workflow",
      params: %{
        "workflow_id" => "notification_batch",
        "input_data" => %{
          "user_data" => "$input",
          "processing_result" => "$nodes.level2_processing"
        },
        "execution_mode" => "fire_and_forget"
      }
    }
  ],
  connections: [
    %Connection{from: "trigger", to: "level1_validation", from_port: "success", to_port: "input"},
    %Connection{from: "level1_validation", to: "level2_processing", from_port: "success", to_port: "input"},
    %Connection{from: "level2_processing", to: "async_notifications", from_port: "success", to_port: "input"}
  ]
}
```

## Node Configuration

### Node Settings

Every node supports optional settings that control execution behavior. Settings are configured using the `Prana.NodeSettings` struct:

```elixir
node_with_settings = %Node{
  id: "api_call",
  custom_id: "api_call", 
  type: :action,
  integration_name: "http",
  action_name: "request",
  params: %{
    url: "https://api.example.com/data",
    method: "GET"
  },
  # Node settings for execution behavior
  settings: %Prana.NodeSettings{
    retry_on_failed: true,
    max_retries: 3,
    retry_delay_ms: 2000
  }
}
```

### Retry Configuration

**Purpose**: Automatically retry failed nodes with configurable delay and attempt limits.

**When to Use Retry**:
- External API calls that might have transient failures
- Network operations prone to timeouts
- Services with occasional unavailability
- Any operation where temporary failures are expected

**Retry Settings**:

```elixir
# Basic retry configuration
basic_retry = %Prana.NodeSettings{
  retry_on_failed: true,    # Enable retry on failure
  max_retries: 3,           # Maximum retry attempts (1-10)
  retry_delay_ms: 1000      # Delay between retries (0-60,000ms)
}

# Conservative retry for critical operations
conservative_retry = %Prana.NodeSettings{
  retry_on_failed: true,
  max_retries: 5,           # More attempts for critical calls
  retry_delay_ms: 5000      # Longer delay for stability
}

# Aggressive retry for reliable services  
aggressive_retry = %Prana.NodeSettings{
  retry_on_failed: true,
  max_retries: 2,           # Fewer attempts for fast feedback
  retry_delay_ms: 500       # Shorter delay for quick retry
}
```

### Retry Examples by Use Case

**HTTP API Calls**:
```elixir
api_node = %Node{
  id: "fetch_user_data",
  custom_id: "fetch_user_data",
  type: :action,
  integration_name: "http", 
  action_name: "request",
  params: %{
    url: "https://api.userservice.com/users/{{input.user_id}}",
    method: "GET",
    headers: %{"Authorization" => "Bearer {{variables.api_token}}"}
  },
  settings: %Prana.NodeSettings{
    retry_on_failed: true,
    max_retries: 3,
    retry_delay_ms: 2000  # 2 second delay for API rate limiting
  }
}
```

**Code Execution**:
```elixir
code_node = %Node{
  id: "data_processing",
  custom_id: "data_processing", 
  type: :action,
  integration_name: "code",
  action_name: "elixir",
  params: %{
    code: "process_data(input)"
  },
  settings: %Prana.NodeSettings{
    retry_on_failed: true,
    max_retries: 2,
    retry_delay_ms: 1000  # Quick retry for code execution
  }
}
```

**External Service Integration**:
```elixir
service_node = %Node{
  id: "payment_processing",
  custom_id: "payment_processing",
  type: :action, 
  integration_name: "payment_service",
  action_name: "charge_card",
  params: %{
    amount: "{{input.amount}}",
    card_token: "{{input.payment_token}}"
  },
  settings: %Prana.NodeSettings{
    retry_on_failed: true,
    max_retries: 4,         # Financial operations need more attempts
    retry_delay_ms: 3000    # Longer delay for payment processing
  }
}
```

### Retry Workflow Patterns

**Simple Retry Chain**:
```elixir
workflow = %Workflow{
  id: "reliable_api_workflow", 
  name: "Reliable API Workflow",
  nodes: [
    # Trigger node
    %Node{
      id: "start",
      custom_id: "start",
      type: :trigger,
      integration_name: "manual",
      action_name: "trigger"
    },
    
    # API call with retry
    %Node{
      id: "api_call",
      custom_id: "api_call", 
      type: :action,
      integration_name: "http",
      action_name: "request",
      params: %{
        url: "https://api.example.com/process",
        method: "POST",
        body: "{{input}}"
      },
      settings: %Prana.NodeSettings{
        retry_on_failed: true,
        max_retries: 3,
        retry_delay_ms: 2000
      }
    },
    
    # Process results
    %Node{
      id: "process_response",
      custom_id: "process_response",
      type: :action, 
      integration_name: "code",
      action_name: "elixir",
      params: %{
        code: "format_response(nodes.api_call)"
      }
    }
  ],
  connections: %{
    "start" => %{
      "main" => [%Connection{from_node: "start", from_port: "main", to_node: "api_call", to_port: "main"}]
    },
    "api_call" => %{
      "main" => [%Connection{from_node: "api_call", from_port: "main", to_node: "process_response", to_port: "main"}]
      # Note: Failed retries will eventually route to error port if all attempts exhausted
    }
  }
}
```

**Mixed Retry/Non-Retry Workflow**:
```elixir
workflow = %Workflow{
  id: "mixed_reliability_workflow",
  name: "Mixed Reliability Workflow", 
  nodes: [
    # Critical API call - needs retry
    %Node{
      id: "critical_api",
      custom_id: "critical_api",
      type: :action,
      integration_name: "http", 
      action_name: "request",
      params: %{url: "https://critical-service.com/api"},
      settings: %Prana.NodeSettings{
        retry_on_failed: true,
        max_retries: 5,         # High retry for critical operation
        retry_delay_ms: 3000
      }
    },
    
    # Local validation - no retry needed
    %Node{
      id: "validate_data",
      custom_id: "validate_data",
      type: :action,
      integration_name: "logic",
      action_name: "if_condition", 
      params: %{condition: "nodes.critical_api.status == 'success'"}
      # No settings - uses defaults (no retry)
    },
    
    # Notification service - quick retry
    %Node{
      id: "send_notification", 
      custom_id: "send_notification",
      type: :action,
      integration_name: "notification_service",
      action_name: "send_email",
      params: %{to: "admin@company.com"},
      settings: %Prana.NodeSettings{
        retry_on_failed: true,
        max_retries: 2,         # Quick failure for notifications
        retry_delay_ms: 1000
      }
    }
  ],
  connections: %{
    "critical_api" => %{
      "main" => [%Connection{from_node: "critical_api", from_port: "main", to_node: "validate_data", to_port: "main"}]
    },
    "validate_data" => %{
      "true" => [%Connection{from_node: "validate_data", from_port: "true", to_node: "send_notification", to_port: "main"}]
    }
  }
}
```

### Retry Best Practices

**Choosing Max Retries**:
- **1-2 retries**: Fast feedback operations, user-facing actions
- **3-4 retries**: Standard API calls, moderate reliability needs
- **5+ retries**: Critical operations, financial transactions

**Setting Retry Delays**:
- **500-1000ms**: Quick internal operations, low-latency services
- **2000-5000ms**: External APIs, rate-limited services
- **5000+ms**: Critical operations, payment processing

**When NOT to Use Retry**:
- Operations with side effects that shouldn't be repeated
- User input validation (errors are permanent)
- Authentication failures (credentials won't suddenly work)
- Resource creation operations (might create duplicates)

## Best Practices

### Node Naming

- Use descriptive, semantic node IDs: `"validate_user"` not `"node1"`
- Match `id` and `custom_id` for consistency
- Use snake_case for node identifiers

### Connection Design

- Always specify both `from_port` and `to_port` explicitly
- Use semantic port names when available (`"premium_flow"` vs `"output1"`)
- Design for failure: consider error routing paths

### Expression Usage

- Use expressions for dynamic data access: `"$input.user_id"`
- Avoid hardcoding values that should come from input or variables
- Use variables for configuration: `"$variables.api_endpoint"`

### Data Flow

- Design clear data flow: input → processing → output
- Use merge nodes to combine parallel processing results
- Consider data types when using merge strategies

### Error Handling

- Plan error routing for critical paths
- Use appropriate timeout values for sub-workflows
- Consider failure strategies: `"fail_parent"` vs `"continue"`

### Performance

- Use `"fire_and_forget"` for non-blocking operations
- Set appropriate timeouts for sub-workflow coordination
- Consider parallel execution for independent operations

## Testing Workflows

### Simple Test Workflow

```elixir
test_workflow = %Workflow{
  id: "test_simple_flow",
  name: "Simple Test Flow",
  nodes: [
    %Node{
      id: "trigger",
      custom_id: "trigger",
      type: :trigger,
      integration_name: "manual",
      action_name: "trigger"
    },
    %Node{
      id: "process",
      custom_id: "process",
      type: :action,
      integration_name: "manual",
      action_name: "process_adult",
      params: "$input"
    }
  ],
  connections: [
    %Connection{
      from: "trigger",
      to: "process",
      from_port: "success",
      to_port: "input"
    }
  ]
}

# Execute test
{:ok, execution_graph} = WorkflowCompiler.compile(test_workflow, "trigger")
{:ok, result, last_output} = GraphExecutor.execute_workflow(execution_graph, %{"user_id" => 123}, %{})
```

### Testing with Variables

```elixir
test_workflow = %Workflow{
  id: "test_with_variables",
  name: "Test with Variables",
  variables: %{
    "api_url" => "https://test-api.example.com",
    "timeout" => 30_000
  },
  nodes: [
    # ... nodes that use $variables.api_url
  ]
}
```

This guide provides the foundation for building complex, robust workflows using Prana's built-in integrations. Combine these patterns to create workflows that handle real-world business processes with proper error handling, data flow, and coordination.
