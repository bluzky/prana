# Prana

**Prana** is a powerful Elixir workflow automation platform built around a node-based graph execution model. It orchestrates complex workflows consisting of nodes (triggers, actions, logic, wait, output) connected through explicit ports with conditional routing and expression-based data flow.

## ✨ Key Features

- **🏗️ Node-Based Architecture**: Visual workflow design with explicit node connections and port-based data routing
- **🔄 Conditional Branching**: Advanced IF/ELSE and switch/case patterns with exclusive path execution
- **🎯 Expression Engine**: Dynamic data access with `$input.field`, `$nodes.api.response`, wildcards, and filtering
- **⚡ Sub-workflow Orchestration**: Synchronous, asynchronous, and fire-and-forget execution modes with suspension/resume
- **🔌 Extensible Integration System**: Clean behavior-driven integration framework with Action behavior pattern
- **🛡️ Type Safety**: All core entities use proper Elixir structs with compile-time checking
- **🚀 Production Ready**: Comprehensive test coverage with 205+ passing tests

## 🏃 Quick Start

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
  nodes: [
    %Prana.Node{
      id: "start",
      custom_id: "start",
      type: :trigger,
      integration_name: "manual",
      action_name: "trigger",
      params: %{},
      output_ports: ["success"]
    },
    %Prana.Node{
      id: "process",
      custom_id: "process", 
      type: :action,
      integration_name: "manual",
      action_name: "process_adult",
      params: %{
        "message" => "$input.message",
        "user" => "$input.user"
      },
      output_ports: ["success"]
    }
  ],
  connections: [
    %Prana.Connection{
      from: "start",
      from_port: "success",
      to: "process",
      to_port: "input"
    }
  ]
}

# 4. Compile and execute
{:ok, execution_graph} = Prana.WorkflowCompiler.compile(workflow, "start")

result = Prana.GraphExecutor.execute_graph(
  execution_graph,
  %{"message" => "Hello", "user" => "World"},
  %{}
)

{:ok, completed_execution} = result
```

## 🧠 Core Concepts

### Workflow Structure

**Workflows** are directed graphs composed of:
- **Nodes**: Individual processing units (triggers, actions, logic, wait, output)
- **Connections**: Explicit port-based routing between nodes
- **Input/Output Ports**: Named channels for data flow
- **Expression Mapping**: Dynamic data transformation using expressions

### Expression System

Access data anywhere in your workflow:

```elixir
# Simple field access
"$input.user.email"                    # Input data
"$nodes.api_call.response.user_id"     # Previous node results  
"$variables.api_url"                   # Workflow variables

# Array operations
"$input.users[0].name"                 # Index access
"$input.users.*.email"                 # Wildcard extraction (returns array)

# Filtering 
"$input.users.{role: \"admin\"}.email"        # Filter by conditions
"$input.orders.{status: \"completed\"}"       # Multiple conditions
```

### Node Types

- **Trigger**: Entry points for workflow execution (HTTP, schedule, manual)
- **Action**: Processing nodes that perform operations (HTTP requests, transformations, custom logic)
- **Logic**: Conditional branching (IF/ELSE, switch/case, merge operations)
- **Wait**: Time-based delays and coordination
- **Output**: Final result processing and responses

### Execution Patterns

**Sequential Execution**: Nodes execute in dependency order
```
A → B → C → D
```

**Conditional Branching**: Exclusive path execution based on conditions
```
A → Condition → (B OR C) → D
```

**Diamond Patterns**: Fork-join execution with data merging
```
A → (B, C) → Merge → D
```

**Sub-workflow Coordination**: Parent-child workflow orchestration
```
A → Sub-workflow(sync/async/fire-forget) → B
```

## 🔌 Built-in Integrations

### Manual Integration
Simple test actions for development and debugging:
- `trigger`: Basic workflow trigger
- `process_adult`/`process_minor`: Data processing actions

### Logic Integration
Conditional workflow control:
- `if_condition`: IF/ELSE branching with true/false ports
- `switch`: Multi-branch routing with named ports

### Data Integration  
Data combination and transformation:
- `merge`: Combine data from multiple sources (append, merge, concat strategies)

### Workflow Integration
Sub-workflow orchestration:
- `execute_workflow`: Synchronous, asynchronous, and fire-and-forget execution modes

## 🛠️ Development

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

## 🏗️ Creating Custom Integrations

### Basic Integration Structure

```elixir
defmodule MyApp.CustomIntegration do
  @behaviour Prana.Behaviour.Integration

  def definition do
    %Prana.Integration{
      name: "custom",
      display_name: "Custom Integration",
      description: "Custom workflow actions",
      actions: %{
        "my_action" => %Prana.Action{
          name: "my_action",
          display_name: "My Action",
          module: MyApp.CustomIntegration.MyAction,
          input_ports: ["input"],
          output_ports: ["success", "error"]
        }
      }
    }
  end

end

defmodule MyApp.CustomIntegration.MyAction do
  @behaviour Prana.Behaviour.Action

  def prepare(_input_map), do: {:ok, %{}}

  def execute(enriched_input) do
    # Access explicitly mapped data
    user_id = enriched_input["user_id"]
    
    # Access full context when needed
    all_input = enriched_input["$input"]
    prev_results = enriched_input["$nodes"]
    variables = enriched_input["$variables"]
    
    # Your logic here
    {:ok, %{result: "processed", user_id: user_id}, "success"}
  end

  def resume(_suspend_data, _resume_input) do
    {:error, "Resume not supported"}
  end
end
```

### Action Return Formats

```elixir
# Simple success
{:ok, result_data}

# Explicit port routing  
{:ok, result_data, "custom_port"}

# Error handling
{:error, error_reason}
{:error, error_reason, "error_port"}

# Suspension for async operations
{:suspend, :custom_suspension_type, suspend_data}
```

### Registration

```elixir
# Register your integration
:ok = Prana.IntegrationRegistry.register_integration(MyApp.CustomIntegration)

# Use in workflows
%Prana.Node{
  integration_name: "custom",
  action_name: "my_action",
  params: %{
    "user_id" => "$input.user_id",
    "api_key" => "$variables.api_key"
  }
}
```

## 📋 Architecture

### Core Components

- **NodeExecutor**: Individual node execution with expression evaluation and suspension/resume
- **GraphExecutor**: Workflow orchestration with conditional branching and sub-workflow coordination
- **WorkflowCompiler**: Optimizes workflows into ExecutionGraphs with O(1) connection lookups
- **ExpressionEngine**: Path-based expression evaluation with wildcards and filtering
- **IntegrationRegistry**: Runtime integration management and action discovery

### Execution Flow

1. **Compilation**: Workflow → ExecutionGraph (optimized for execution)
2. **Initialization**: Create execution context with input data and variables
3. **Node Execution**: Sequential execution following dependencies and conditions
4. **Expression Evaluation**: Dynamic data access and transformation
5. **Port Routing**: Data flow through explicit connections
6. **Completion**: Final execution state with all node results

### Design Principles

- **Type Safety**: Compile-time validation with Elixir structs
- **Explicit Data Flow**: No hidden dependencies, clear port-based routing
- **Behavior-Driven**: Clean contracts for extensibility
- **Suspension/Resume**: First-class support for async operations
- **Middleware Integration**: Event-driven lifecycle hooks

## 📚 Documentation

- **[Writing Integrations Guide](docs/guides/writing_integrations.md)**: Comprehensive integration development guide
- **[Building Workflows Guide](docs/guides/building_workflows.md)**: Workflow composition patterns and best practices
- **[Built-in Integrations](docs/built-in-integrations.md)**: Complete reference for all built-in actions
- **[Architecture Documentation](docs/)**: Detailed implementation and design docs

## 🧪 Testing

Prana has comprehensive test coverage:
- **205+ tests** covering all core functionality
- **Unit tests** for individual components
- **Integration tests** for complete workflow execution
- **Performance tests** for optimization validation

```bash
# Current test status
mix test
# => 205 tests, 0 failures
```

## 📈 Implementation Status

**Overall Progress**: ~95% Complete (Production Ready Core Platform)

### ✅ Complete
- Core execution engine (NodeExecutor, GraphExecutor)
- All built-in integrations (Manual, Logic, Data, Workflow)
- Sub-workflow orchestration with suspension/resume
- Conditional branching (IF/ELSE, switch/case patterns)
- Expression engine with wildcards and filtering
- Integration registry and middleware system
- Comprehensive test coverage

### 🎯 Future Enhancements
- Additional integrations (HTTP, Transform, Wait, Log)
- Enhanced error handling and retry policies
- Performance optimizations for large workflows
- Workflow builder and validation tools

## 🤝 Contributing

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

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- Built with ❤️ using Elixir and OTP
- Inspired by modern workflow orchestration platforms
- Designed for developer productivity and type safety

---

**Ready to build powerful workflows?** Check out the [Quick Start](#-quick-start) guide and start orchestrating your processes with Prana! 🚀