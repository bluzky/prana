# Prana

**Prana** is a powerful Elixir workflow automation platform built around a node-based graph execution model. It orchestrates complex workflows consisting of nodes (triggers, actions, logic, wait, output) connected through explicit ports with conditional routing and expression-based data flow.

## Key Features

- **Node-Based Architecture**: Visual workflow design with explicit node connections and port-based data routing
- **Conditional Branching**: Advanced IF/ELSE and switch/case patterns with exclusive path execution
- **Template Engine**: Dynamic data access with `{{ $input.field }}`, `{{ $nodes.api.response }}`, filters, and expressions
- **Sub-workflow Orchestration**: Synchronous, asynchronous, and fire-and-forget execution modes with suspension/resume
- **Extensible Integration System**: Clean behavior-driven integration framework with Action behavior pattern
- **Type Safety**: All core entities use proper Elixir structs with compile-time checking
- **Production Ready**: Comprehensive test coverage with 353+ passing tests

## Quick Start

### Installation

Add `prana` to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:prana, "~> 0.1.0"}
  ]
end
```

### Basic Usage

```elixir
# 1. Start the integration registry
{:ok, _registry} = Prana.IntegrationRegistry.start_link()

# 2. Register built-in integrations
:ok = Prana.IntegrationRegistry.register_integration(Prana.Integrations.Manual)
:ok = Prana.IntegrationRegistry.register_integration(Prana.Integrations.Logic)

# 3. Create a simple workflow
workflow = %Prana.Workflow{
  id: "hello_world",
  name: "Hello World Workflow",
  version: 1,
  nodes: [
    %Prana.Node{
      key: "start",
      name: "Start Trigger",
      type: "manual.trigger",
      params: %{}
    },
    %Prana.Node{
      key: "process",
      name: "Process Data",
      type: "manual.process_adult",
      params: %{
        "message" => "{{ $input.message }}",
        "user" => "{{ $input.user }}"
      }
    }
  ],
  connections: %{
    "start" => %{
      "main" => [
        %Prana.Connection{
          from: "start",
          from_port: "main",
          to: "process",
          to_port: "main"
        }
      ]
    }
  },
  variables: %{}
}

# 4. Compile and execute
{:ok, execution_graph} = Prana.WorkflowCompiler.compile(workflow, "start")

result = Prana.GraphExecutor.execute_workflow(
  execution_graph,
  %{"message" => "Hello", "user" => "World"},
  %{}
)

{:ok, completed_execution} = result
```

## Core Concepts

### Workflow Structure

**Workflows** are directed graphs composed of:
- **Nodes**: Individual processing units (triggers, actions, logic, wait, output)
- **Connections**: Explicit port-based routing between nodes
- **Input/Output Ports**: Named channels for data flow
- **Expression Mapping**: Dynamic data transformation using expressions

### Template System

Access data anywhere in your workflow:

```elixir
# Simple field access
"{{ $input.user.email }}"                    # Input data
"{{ $nodes.api_call.response.user_id }}"     # Previous node results  
"{{ $variables.api_url }}"                   # Workflow variables

# Array operations
"{{ $input.users[0].name }}"                 # Index access
"{{ $input.users }}"                         # Full arrays

# Arithmetic and boolean expressions
"{{ $input.age + 10 }}"                      # Math operations
"{{ $input.age >= 18 && $input.verified }}" # Boolean logic

# Filters
"{{ $input.name | upper_case }}"             # Transform data
"{{ $input.price | format_currency('USD') }}" # Formatted output
```

### Node Types

- **Trigger**: Entry points for workflow execution (HTTP webhooks, cron schedules, manual triggers)
- **Action**: Processing nodes that perform operations (HTTP requests, data transformations, custom logic)
- **Logic**: Conditional branching (IF/ELSE, switch/case, merge operations)
- **Wait**: Time-based delays and coordination
- **Output**: Final result processing and responses


## Built-in Integrations

### Manual Integration
Simple test actions for development and debugging:
- `trigger`: Basic workflow trigger
- `process_adult`/`process_minor`: Data processing actions

### HTTP Integration
HTTP requests and webhooks:
- `request`: Make HTTP requests with full configuration support
- `webhook`: Handle incoming webhook requests and responses

### Schedule Integration
Time-based workflow triggers:
- `cron_trigger`: Schedule workflows with cron expressions

### Logic Integration
Conditional workflow control:
- `if_condition`: IF/ELSE branching with true/false ports
- `switch`: Multi-branch routing with named ports

### Data Integration  
Data combination and transformation:
- `merge`: Combine data from multiple sources (append, merge, concat strategies)
- `set_data`: Set workflow variables and state

### Wait Integration
Time-based coordination:
- Delay actions and timeout handling for time-based workflows

### Workflow Integration
Sub-workflow orchestration:
- `execute_workflow`: Synchronous, asynchronous, and fire-and-forget execution modes
- `set_state`: Manage workflow state and variables

## Development

### Setup
```bash
# Get dependencies
mix deps.get

# Compile project
mix compile

# Run tests
mix test

# Code analysis
mix credo

# Format code
mix format
```

### Testing
```bash
# Run all tests
mix test

# Run specific test file
mix test test/prana/node_executor_test.exs

# Detailed test output
mix test --trace

# Watch mode
mix test.watch
```

### Interactive Development
```bash
# Start IEx with project loaded
iex -S mix

# Quick test in IEx
iex> {:ok, _} = Prana.IntegrationRegistry.start_link()
iex> Prana.IntegrationRegistry.register_integration(Prana.Integrations.Manual)
```

## Creating Custom Integrations

For detailed guidance on creating custom integrations, see the [Writing Integrations Guide](docs/guides/writing_integrations.md). This comprehensive guide covers:

- Integration and Action behavior implementation
- Template processing and context handling
- Action return formats and error handling
- Suspension/resume patterns for async operations
- Registration and usage in workflows
- Testing strategies and best practices

## Architecture

### Core Components

- **NodeExecutor**: Individual node execution with expression evaluation and suspension/resume
- **GraphExecutor**: Workflow orchestration with conditional branching and sub-workflow coordination
- **WorkflowCompiler**: Optimizes workflows into ExecutionGraphs with O(1) connection lookups
- **TemplateEngine**: Template rendering with expressions, filters, and data interpolation
- **IntegrationRegistry**: Runtime integration management and action discovery

### Execution Flow

1. **Compilation**: Workflow → ExecutionGraph (optimized for execution)
2. **Initialization**: Create execution context with input data and variables
3. **Node Execution**: Sequential execution following dependencies and conditions
4. **Template Processing**: Dynamic data access, expressions, and filters
5. **Port Routing**: Data flow through explicit connections
6. **Completion**: Final execution state with all node results

### Design Principles

- **Type Safety**: Compile-time validation with Elixir structs
- **Explicit Data Flow**: No hidden dependencies, clear port-based routing
- **Behavior-Driven**: Clean contracts for extensibility
- **Suspension/Resume**: First-class support for async operations
- **Middleware Integration**: Event-driven lifecycle hooks

## Documentation

- **[Writing Integrations Guide](docs/guides/writing_integrations.md)**: Comprehensive integration development guide
- **[Building Workflows Guide](docs/guides/building_workflows.md)**: Workflow composition patterns and best practices
- **[Built-in Integrations](docs/built-in-integrations.md)**: Complete reference for all built-in actions
- **[Architecture Documentation](docs/)**: Detailed implementation and design docs

## Testing

Prana has comprehensive test coverage:
- **353+ tests** covering all core functionality
- **Unit tests** for individual components
- **Integration tests** for complete workflow execution
- **Performance tests** for optimization validation

```bash
# Current test status
mix test
# => 353 tests, 0 failures
```

## Implementation Status

**Overall Progress**: ~98% Complete (Production Ready Platform)

### Complete
- Core execution engine (NodeExecutor, GraphExecutor)
- All built-in integrations (Manual, HTTP, Schedule, Logic, Data, Wait, Workflow)
- Sub-workflow orchestration with suspension/resume
- Conditional branching (IF/ELSE, switch/case patterns)
- Template engine with expressions, filters, and data interpolation
- Integration registry and middleware system
- Comprehensive test coverage with 353+ tests
- HTTP requests and webhook handling
- Time-based scheduling with cron triggers

### Future Enhancements
- Additional integrations (Transform, Log, Database)
- Enhanced error handling and retry policies
- Performance optimizations for large workflows
- Workflow builder and validation tools
- Advanced scheduling features

## Contributing

1. **Fork the repository**
2. **Create a feature branch**: `git checkout -b feature/amazing-feature`
3. **Run tests**: `mix test`
4. **Add tests for new functionality**
5. **Commit changes**: `git commit -m 'Add amazing feature'`
6. **Push to branch**: `git push origin feature/amazing-feature`
7. **Create Pull Request**

### Development Guidelines

- Follow existing code patterns and conventions
- Add comprehensive tests for new features
- Update documentation for API changes
- Use `mix credo` for code quality checks
- Format code with `mix format`

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Built with Elixir and OTP
- Inspired by modern workflow orchestration platforms
- Designed for developer productivity and type safety

---

**Ready to build powerful workflows?** Check out the [Quick Start](#quick-start) guide and start orchestrating your processes with Prana!