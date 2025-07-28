# Elixir Code Execution Integration - Task Specification

## Overview

Implement a Code integration for Prana that supports secure execution of user-provided Elixir code. This integration focuses exclusively on Elixir code execution with robust sandboxing and security measures, inspired by Sequin's MiniElixir approach.

## Key Insights from Sequin's MiniElixir (ACTUAL Implementation)

Based on analysis of Sequin's actual MiniElixir implementation (`lib/sequin/functions/minielixir.ex`):

1. **Dual Execution Modes**: 
   - `run_interpreted`: Uses `Code.eval_quoted_with_env` for validation/testing
   - `run_compiled`: Compiles to dynamic modules for production execution

2. **Dynamic Module Naming**: Uses function IDs as module names (`"UserFunction.#{id}"`)

3. **Module Lifecycle Management**: 
   - `compile_and_load!/1`: Compiles AST and loads with `:code.load_binary`
   - `ensure_code_is_loaded/1`: Checks and recreates modules as needed

4. **Performance**: 1000ms timeout, optimized for high-throughput execution

5. **Strict Validation**: AST validation using their validator before any execution

6. **Error Handling**: Comprehensive error encoding with telemetry and logging

## Architecture

### Integration Structure
```
lib/prana/integrations/code.ex  # Main integration module
└── ElixirCodeAction           # Execute Elixir code with process isolation
```

### Supporting Modules
```
lib/prana/integrations/code/
├── elixir_code_action.ex     # Main Elixir code execution action
├── sandbox.ex               # Elixir-specific sandboxing utilities
├── ast_validator.ex         # AST validation and filtering
└── security_policy.ex       # Elixir security policy configuration
```

## Task Breakdown

### Task 1: Core Integration Setup
**Priority: High**
**Estimated Effort: 1-2 hours**

Create the main Code integration module following Prana patterns:

```elixir
defmodule Prana.Integrations.Code do
  @behaviour Prana.Behaviour.Integration

  alias Prana.Integration
  alias Prana.Integrations.Code.ElixirCodeAction

  def definition do
    %Integration{
      name: "code",
      display_name: "Code Execution",
      description: "Execute Elixir code in a sandboxed environment",
      version: "1.0.0",
      category: "development",
      actions: %{
        "elixir" => ElixirCodeAction.specification()
      }
    }
  end
end
```

**Deliverables:**
- Main integration module
- ElixirCodeAction specification
- Integration registration with Prana.IntegrationRegistry

### Task 2: ElixirCodeAction Implementation
**Priority: High**
**Estimated Effort: 6-8 hours**

Implement secure Elixir code execution using process isolation and custom sandboxing.

**Security Approach:**
- Process-based isolation using `Task.Supervisor`
- Custom allowlist for safe modules/functions
- AST filtering to prevent dangerous operations
- Custom sandboxing using `Code.eval_quoted` with restricted bindings
- Process timeout and memory monitoring

**Action Specification:**
```elixir
%Action{
  name: "code.elixir",
  display_name: "Execute Elixir Code",
  description: "Execute Elixir code in a sandboxed environment",
  type: :action,
  input_ports: ["input"],
  output_ports: ["success", "error"],
  params_schema: %{
    "code" => %{type: "string", required: true, description: "Elixir code to execute"},
    "timeout" => %{type: "integer", default: 5000, description: "Timeout in milliseconds"},
    "memory_limit" => %{type: "integer", default: 10_000_000, description: "Memory limit in bytes"},
    "allowed_modules" => %{type: "array", default: ["Enum", "String", "Integer"], description: "Allowed modules"}
  }
}
```

**Implementation Details:**
```elixir
defmodule Prana.Integrations.Code.ElixirCodeAction do
  use Prana.Actions.SimpleAction
  
  alias Prana.Action
  alias Prana.Integrations.Code.{Sandbox, AstValidator, SecurityPolicy}
  
  def specification do
    %Action{
      name: "code.elixir",
      display_name: "Execute Elixir Code",
      description: "Execute Elixir code in a sandboxed environment",
      type: :action,
      module: __MODULE__,
      input_ports: ["input"],
      output_ports: ["success", "error"]
    }
  end
  
  def execute(params, context) do
    code = params["code"]
    timeout = params["timeout"] || 5000
    allowed_modules = params["allowed_modules"] || SecurityPolicy.default_allowed_modules()
    
    # Validate and filter AST
    case AstValidator.validate_code(code, allowed_modules) do
      {:ok, ast} ->
        # Execute in supervised process with timeout
        Sandbox.execute_in_sandbox(ast, timeout, context)
      {:error, reason} ->
        {:error, "Code validation failed: #{reason}"}
    end
  end
end
```

**Deliverables:**
- ElixirCodeAction module with full sandboxing
- AST validation and filtering utilities
- Process supervision and timeout handling
- Memory monitoring and cleanup
- Comprehensive test suite

### Task 3: AST Validator Implementation (Sequin-Inspired)
**Priority: High**
**Estimated Effort: 4-5 hours**

Implement AST validation using Sequin's proven whitelist-only approach.

**Security Approach (Based on Sequin MiniElixir):**
- Parse code into AST (nested tuples) using `Code.string_to_quoted/1`
- Traverse AST and **only allow** operators/functions in strict whitelist
- Reject any code that contains non-whitelisted operations
- Focus on performance with simple AST traversal

**Sequin-Inspired Whitelist:**
```elixir
defmodule Prana.Integrations.Code.AstValidator do
  @moduledoc """
  AST validator inspired by Sequin's MiniElixir whitelist-only approach.
  """
  
  # Whitelisted operators (based on Sequin's approach)
  @allowed_operators [
    :+, :-, :*, :/, :div, :rem,
    :==, :!=, :<, :>, :<=, :>=,
    :and, :or, :not, :&&, :||, :!,
    :++, :--, :in, :|>, :=
  ]
  
  # Whitelisted Kernel functions (safe subset)
  @allowed_kernel_functions [
    :abs, :binary_part, :bit_size, :byte_size, :ceil, :elem, :floor,
    :hd, :tl, :length, :map_size, :tuple_size, :round, :trunc,
    :is_integer, :is_float, :is_binary, :is_list, :is_map, :is_tuple
  ]
  
  # Whitelisted modules (very restricted)
  @allowed_modules [
    Enum, String, Integer, Float, Map, List, Tuple
  ]
  
  def validate_code(code) do
    case Code.string_to_quoted(code) do
      {:ok, ast} ->
        case traverse_and_validate(ast) do
          :ok -> {:ok, ast}
          {:error, reason} -> {:error, reason}
        end
      {:error, reason} ->
        {:error, "Parse error: #{inspect(reason)}"}
    end
  end
  
  defp traverse_and_validate(ast) do
    # Traverse AST tuples and validate each node
    case validate_node(ast) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp validate_node({operator, _meta, args}) when operator in @allowed_operators do
    # Recursively validate arguments
    validate_args(args)
  end
  
  defp validate_node({{:., _meta, [{:__aliases__, _, module}, function]}, _meta2, args}) do
    # Module function call - check whitelist
    if List.first(module) in @allowed_modules do
      validate_args(args)
    else
      {:error, "Module #{inspect(module)} not allowed"}
    end
  end
  
  defp validate_node({function, _meta, args}) when function in @allowed_kernel_functions do
    validate_args(args)
  end
  
  defp validate_node(literal) when is_atom(literal) or is_number(literal) or is_binary(literal) do
    :ok  # Literals are safe
  end
  
  defp validate_node(node) do
    {:error, "Operation #{inspect(node)} not allowed"}
  end
  
  defp validate_args(nil), do: :ok
  defp validate_args(args) when is_list(args) do
    Enum.reduce_while(args, :ok, fn arg, :ok ->
      case validate_node(arg) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end
end
```

**Key Security Features:**
- **Whitelist-only**: Reject anything not explicitly allowed
- **No binary operators**: Block `<<`/`>>` to prevent massive binary generation
- **Limited modules**: Only safe data manipulation modules
- **Performance focused**: Simple traversal without complex analysis

**Deliverables:**
- AstValidator with Sequin-inspired whitelist approach
- Comprehensive operator and function whitelist
- Fast AST traversal with early rejection
- Security-first validation (deny by default)
- Test suite including attack vector validation

### Task 4: Sandbox Implementation (Sequin's Exact Pattern)
**Priority: High**
**Estimated Effort: 6-8 hours**

Implement Sequin's proven dual-mode execution pattern with exact implementation details.

**Execution Modes (Sequin's Actual Pattern):**
1. **run_interpreted**: Use `Code.eval_quoted_with_env` for validation/development
2. **run_compiled**: Compile to dynamic modules for production execution  
3. **Module Management**: Use function IDs as module names, proper lifecycle management

**Implementation Details (Sequin's Exact Pattern):**
```elixir
defmodule Prana.Integrations.Code.Sandbox do
  @moduledoc """
  Elixir code sandbox implementing Sequin's exact MiniElixir pattern.
  Uses run_interpreted for validation, run_compiled for execution.
  """
  
  @timeout 1000  # Sequin uses 1000ms timeout
  
  # Sequin's run_interpreted pattern (for validation/development)
  def run_interpreted(code_id, ast, context) do
    Task.async(fn ->
      validated_ast = validate_ast(ast)  # Use Sequin's validator
      
      # Create bindings like Sequin (action, record, changes, metadata)
      bindings = create_bindings(context)
      
      # Use Code.eval_quoted_with_env like Sequin
      {result, _new_bindings} = Code.eval_quoted_with_env(
        validated_ast,
        bindings,
        __ENV__
      )
      
      {:ok, result}
    end)
    |> Task.await(@timeout)
  rescue
    error -> encode_error(error)  # Sequin's error encoding
  end
  
  # Sequin's run_compiled pattern (for production execution)
  def run_compiled(code_id, ast, context) do
    Task.async(fn ->
      module_name = generate_module_name(code_id)  # "UserFunction.#{id}"
      
      # Ensure module is loaded (Sequin's pattern)
      ensure_code_is_loaded(module_name, ast, context)
      
      # Call the compiled module's run function
      bindings = create_bindings(context)
      result = apply(module_name, :run, Map.values(bindings))
      
      {:ok, result}
    end)
    |> Task.await(@timeout)
  rescue
    error -> encode_error(error)
  end
  
  # Sequin's module naming pattern
  defp generate_module_name(code_id) do
    :"UserFunction.#{code_id}"  # Exact Sequin pattern
  end
  
  # Sequin's ensure_code_is_loaded pattern
  defp ensure_code_is_loaded(module_name, ast, context) do
    case Code.ensure_loaded(module_name) do
      {:module, ^module_name} -> 
        :ok  # Module already loaded
      {:error, :nofile} ->
        compile_and_load(module_name, ast, context)
    end
  end
  
  # Sequin's compile_and_load pattern
  defp compile_and_load(module_name, ast, context) do
    validated_ast = validate_ast(ast)
    bindings = create_bindings(context)
    
    # Create module AST like Sequin
    module_ast = create_module_ast(module_name, validated_ast, bindings)
    
    # Compile and load with :code.load_binary (Sequin's approach)
    [{^module_name, bytecode}] = Code.compile_quoted(module_ast)
    :code.load_binary(module_name, '#{module_name}.beam', bytecode)
  end
  
  # Create module AST (Sequin's create_expr pattern)
  defp create_module_ast(module_name, user_ast, bindings) do
    arglist = Enum.map(bindings, fn {key, _} -> 
      Macro.var(key, :"Elixir")  # Sequin uses :"Elixir" context
    end)
    
    quote do
      defmodule unquote(module_name) do
        def run(unquote_splicing(arglist)) do
          unquote(user_ast)
        end
      end
    end
  end
  
  # Create bindings for Prana context (adapted from Sequin's pattern)
  defp create_bindings(context) do
    %{
      input: context["$input"] || %{},
      nodes: context["$nodes"] || %{},
      variables: context["$variables"] || %{},
      env: context["$env"] || %{}
    }
  end
  
  # Validate AST using Sequin's validator
  defp validate_ast(ast) do
    # Call our AstValidator (Task 3) which implements Sequin's validation
    case Prana.Integrations.Code.AstValidator.validate_code_ast(ast) do
      {:ok, validated_ast} -> validated_ast
      {:error, reason} -> raise "Validation failed: #{reason}"
    end
  end
  
  # Sequin's error encoding pattern
  defp encode_error(error) do
    {:error, %{
      type: error.__struct__,
      message: Exception.message(error),
      details: Exception.format(:error, error)
    }}
  end
end
```

**Performance Benefits:**
- **Compiled Mode**: Optimized for repeated execution with compiled bytecode
- **Target Performance**: <10μs execution time (based on Sequin's overall benchmark)
- **Dynamic Module Cleanup**: Automatic memory management  
- **Dual Mode**: Choose optimal execution strategy per use case

**Deliverables:**
- Dual-mode sandbox (compiled + interpreted)
- Dynamic module generation and cleanup
- Process isolation with timeout handling
- Performance benchmarking and optimization
- Comprehensive error handling and resource cleanup
- Security testing for both execution modes

### Task 5: Security Policy Implementation
**Priority: High**
**Estimated Effort: 2-3 hours**

Implement configurable security policies for Elixir code execution.

**Security Configuration:**
- Define default allowlist of safe modules and functions
- Configurable blocklist for dangerous operations
- Resource limits (timeout, memory, processes)
- Runtime policy validation and enforcement

**Implementation Details:**
```elixir
defmodule Prana.Integrations.Code.SecurityPolicy do
  @moduledoc """
  Security policy configuration for Elixir code execution.
  """
  
  @default_allowed_modules [
    "Enum", "String", "Integer", "Float", "Map", "List",
    "Kernel", "Base", "DateTime", "Date", "Time", "URI"
  ]
  
  @blocked_functions [
    {"File", :*},
    {"System", :*},
    {"Process", :*},
    {:os, :*},
    {"Code", :*},
    {"Module", :*},
    {:erlang, :*}
  ]
  
  @default_limits %{
    max_execution_time: 5000,  # milliseconds
    max_memory_mb: 10,         # megabytes
    max_processes: 1           # concurrent processes
  }
  
  def default_allowed_modules, do: @default_allowed_modules
  def blocked_functions, do: @blocked_functions
  def default_limits, do: @default_limits
  
  def validate_policy(policy) do
    # Validate policy configuration
  end
  
  def is_allowed_call?(module, function) do
    # Check if module/function call is allowed
  end
  
  def apply_limits(params) do
    # Apply resource limits to execution parameters
  end
end
```

**Deliverables:**
- SecurityPolicy module with comprehensive configuration
- Default security settings for safe execution
- Policy validation and enforcement utilities
- Runtime security checks
- Documentation for security configuration

### Task 6: Dependencies and Environment Setup
**Priority: Medium**
**Estimated Effort: 1-2 hours**

Add required dependencies and configure the environment for Elixir code execution.

**Implementation Approach:**
- Implement custom sandboxing using process isolation
- Use `Code.eval_quoted/3` with restricted bindings
- Implement resource monitoring and cleanup
- No external sandboxing dependencies required

**Implementation Considerations:**
```elixir
# Fallback sandbox implementation
defmodule Prana.Integrations.Code.CustomSandbox do
  def eval_safely(ast, binding, timeout) do
    # Custom implementation using Task.Supervisor and Code.eval_quoted
  end
  
  def create_restricted_binding(context) do
    # Create safe variable binding
  end
  
  def monitor_execution(pid, limits) do
    # Monitor memory and execution time
  end
end
```

**Deliverables:**
- Updated mix.exs with required dependencies
- Fallback implementation for custom sandboxing
- Environment validation and setup utilities
- Documentation for dependency requirements

### Task 7: Comprehensive Testing
**Priority: High**
**Estimated Effort: 3-4 hours**

Implement comprehensive test suite for all components.

**Test Categories:**

**Unit Tests:**
- ElixirCodeAction execution paths
- AST validation and filtering
- Security policy enforcement
- Sandbox isolation and cleanup

**Security Tests:**
```elixir
# Test dangerous code execution attempts
test "blocks file system access" do
  code = "File.read!('/etc/passwd')"
  assert {:error, _} = ElixirCodeAction.execute(%{"code" => code}, %{})
end

test "blocks system calls" do
  code = "System.cmd('rm', ['-rf', '/'])"
  assert {:error, _} = ElixirCodeAction.execute(%{"code" => code}, %{})
end

test "enforces timeout limits" do
  code = ":timer.sleep(10000)"
  assert {:error, "Execution timeout"} = ElixirCodeAction.execute(%{"code" => code, "timeout" => 1000}, %{})
end
```

**Integration Tests:**
- Full workflow execution with code actions
- Context variable injection and access
- Error handling and recovery
- Resource cleanup after execution

**Deliverables:**
- Comprehensive test suite covering all modules
- Security penetration tests
- Performance and resource limit tests
- CI/CD integration for automated testing


## Testing Strategy

### Unit Tests
- ElixirCodeAction with comprehensive test coverage
- AST validation and filtering tests
- Security policy validation tests
- Sandbox escape attempt tests
- Resource limit enforcement tests

### Integration Tests
- Full workflow execution with Elixir code actions
- Context variable injection and access
- Error handling and recovery tests
- Performance and timeout tests

### Security Tests
- Attempted file system access (File module)
- System command execution attempts
- Process spawning and manipulation
- Memory and CPU resource exhaustion
- Code injection and AST manipulation attempts

## Success Criteria

1. **Security**: Elixir code executes in properly isolated environment with no escape paths
2. **Performance**: Actions complete within specified timeouts (default 5 seconds)
3. **Reliability**: Robust error handling and automatic resource cleanup
4. **Usability**: Clear parameter schema and intuitive configuration
5. **Safety**: Comprehensive blocklist prevents dangerous operations
6. **Integration**: Seamless integration with Prana workflow system and expression engine

## Risk Mitigation

1. **Security Vulnerabilities**: Comprehensive AST validation and process isolation
2. **Resource Exhaustion**: Strict timeout and memory limits with automatic cleanup
3. **Sandbox Escapes**: Multiple layers of protection (AST filtering, process isolation, restricted bindings)
4. **Performance Impact**: Asynchronous execution with supervised tasks
5. **Memory Leaks**: Automatic process cleanup and garbage collection
6. **Atom Table Overflow**: Prevention of dynamic atom creation in user code

## Updated Implementation Plan (Sequin-Inspired)

### Phase 1: Core Security Foundation (Days 1-3)
**Priority: Establish rock-solid security first**

1. **AST Validator (Sequin-Inspired)** - Task 3 moved to Priority #1
   - Implement proven whitelist-only approach
   - Block dangerous operations at AST level
   - Target <1μs validation time

2. **Security Policy** - Task 5 elevated  
   - Define strict whitelists based on Sequin's model
   - Deny-by-default security posture
   - Resource limit definitions

3. **Core Integration Setup** - Task 1
   - Basic Prana integration structure
   - ElixirCodeAction specification

### Phase 2: High-Performance Execution (Days 4-5)
**Priority: Achieve <10μs execution target**

4. **Sandbox Implementation** - Task 4 enhanced
   - Process isolation with heap limits
   - Performance-optimized Code.eval_quoted execution  
   - Microsecond-level monitoring

5. **ElixirCodeAction Integration** - Task 2 refined
   - Integrate AST validation with execution
   - Performance optimization and caching
   - Context variable injection

### Phase 3: Production Hardening (Days 6-7)
**Priority: Production-ready security and reliability**

6. **Performance Optimization** - New focus area
   - Profile and optimize for <10μs target
   - Memory allocation optimization
   - Process pool management

7. **Comprehensive Security Testing** - Task 7 expanded
   - Binary generation attack tests
   - Resource exhaustion scenarios
   - AST manipulation attempts
   - Performance regression testing

## Revised Success Criteria (Sequin-Inspired)

1. **Security**: Whitelist-only execution with zero dangerous operation escapes
2. **Performance**: <10μs execution time (Sequin's benchmark)
3. **Reliability**: Process isolation with automatic cleanup and resource limits
4. **Production-Ready**: Comprehensive security testing against known attack vectors
5. **Prana Integration**: Seamless workflow integration with expression engine support

**Total Estimated Effort: 22-28 hours over 1 week**
**Key Change: Security-first approach with proven patterns**