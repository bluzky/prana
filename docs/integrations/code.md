# Code Integration

The Code integration provides secure execution of user-provided Elixir code within Prana workflows. It implements a robust sandboxing system based on Sequin's proven MiniElixir patterns, ensuring safe execution while maintaining high performance.

## Overview

**Module**: `Prana.Integrations.Code`  
**Category**: Development  
**Security**: Whitelist-only validation with process isolation  
**Performance**: Dual-mode execution (interpreted/compiled)

## Actions

### elixir - Execute Elixir Code

Executes user-provided Elixir code in a secure sandbox environment with comprehensive security validation.

**Action Name**: `code.elixir`  
**Type**: Action  
**Input Ports**: `["input"]`  
**Output Ports**: `["success", "error"]`

#### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `code` | string | ✅ | - | Elixir code containing `def run(input, context)` function |

#### Context Variables

The executed code receives two parameters:

1. **`input`** - The workflow input data from `$input`
2. **`context`** - Complete workflow context containing:
   - `input` - Same as first parameter for convenience
   - `nodes` - Results from previous nodes (`$nodes`)
   - `vars` - Workflow variables (`$vars`) 
   - `env` - Environment variables (`$env`)
   - `execution` - Execution metadata (`$execution`)

#### Example Usage

```elixir
# Simple data transformation
%{
  "action" => "code.elixir",
  "params" => %{
    "code" => """
    def run(input, _context) do
      name = input["name"]
      age = input["age"]
      
      "Hello #{name}, you are #{age} years old"
    end
    """
  }
}

# Using context variables
%{
  "action" => "code.elixir", 
  "params" => %{
    "code" => """
    def run(input, context) do
      user_name = input["name"]
      api_response = context.nodes["api_call"]["response"]
      environment = context.env["environment"]
      
      %{
        "greeting" => "Hello #{user_name}",
        "api_data" => api_response,
        "env" => environment
      }
    end
    """
  }
}

# Data processing and validation
%{
  "action" => "code.elixir",
  "params" => %{
    "code" => """
    def run(input, _context) do
      numbers = input["numbers"]
      
      numbers
      |> Enum.filter(fn x -> x > 0 end)
      |> Enum.map(fn x -> x * 2 end)
      |> Enum.sum()
    end
    """
  }
}
```

#### Return Value

**Success**: `{:ok, %{result: value}}`  
**Error**: `{:error, error_message}`

The `result` field contains whatever value your `run/2` function returns.

## Security Model

The Code integration implements a security-first approach with multiple layers of protection:

### 1. AST-Level Validation

All code is parsed into an Abstract Syntax Tree (AST) and validated against strict whitelists before execution:

- **Function signature validation**: Only `def run(input, context)` functions are allowed
- **Operation whitelisting**: Only explicitly approved operators and functions are permitted
- **Module restrictions**: Only safe modules are accessible

### 2. Process Isolation

Code execution occurs in isolated processes with:

- **Timeout protection**: 1000ms execution limit
- **Process supervision**: Automatic cleanup on failure
- **Memory isolation**: No shared state between executions

### 3. Whitelist-Only Security

Based on Sequin's proven security model, only explicitly approved operations are allowed.

## Supported Operations

### Arithmetic Operators
```elixir
+, -, *, /, rem, div
```

### Comparison Operators
```elixir
==, !=, <, >, <=, >=
```

### Logical Operators
```elixir
and, or, not, &&, ||, !
```

### List Operators
```elixir
++, --
```

### String/Pipeline Operators
```elixir
|>, <>, =~
```

### Membership Operator
```elixir
in
```

## Supported Modules and Functions

### String Module
```elixir
String.length/1
String.trim/1
String.upcase/1
String.downcase/1
String.capitalize/1
String.contains?/2
String.starts_with?/2
String.ends_with?/2
String.slice/2, String.slice/3
String.split/2
String.replace/3, String.replace/4
String.to_integer/1
String.to_float/1
String.to_atom/1
```

### Enum Module
```elixir
Enum.map/2
Enum.filter/2
Enum.reduce/3
Enum.find/2
Enum.any?/2, Enum.all?/2
Enum.count/1, Enum.count/2
Enum.empty?/1
Enum.member?/2
Enum.at/2
Enum.first/1, Enum.last/1
Enum.take/2, Enum.drop/2
Enum.reverse/1
Enum.sort/1, Enum.sort/2
Enum.uniq/1
Enum.join/2
Enum.concat/2
Enum.flat_map/2
```

### Map Module
```elixir
Map.get/2, Map.get/3
Map.put/3
Map.delete/2
Map.has_key?/2
Map.keys/1, Map.values/1
Map.merge/2
Map.new/0
Map.size/1
```

### List Module
```elixir
List.first/1
List.last/1
List.wrap/1
List.flatten/1
```

### Kernel Functions
```elixir
length/1
hd/1, tl/1
is_atom/1, is_binary/1, is_boolean/1
is_float/1, is_integer/1, is_list/1
is_map/1, is_nil/1, is_number/1, is_tuple/1
max/2, min/2
abs/1, round/1, trunc/1, floor/1, ceil/1
elem/2, tuple_size/1
```

### DateTime, Date, Time Modules
```elixir
DateTime.utc_now/0, DateTime.to_string/1
DateTime.to_date/1, DateTime.to_time/1
DateTime.add/3, DateTime.diff/2, DateTime.compare/2

Date.utc_today/0, Date.to_string/1
Date.add/2, Date.diff/2, Date.compare/2

Time.utc_now/0, Time.to_string/1
Time.add/2, Time.diff/2, Time.compare/2
```

### Numeric Modules
```elixir
Integer.to_string/1, Integer.parse/1
Float.to_string/1, Float.parse/1
Float.round/1, Float.round/2
Float.ceil/1, Float.floor/1
```

### Regex Module
```elixir
Regex.match?/2
Regex.run/2
Regex.scan/2
Regex.replace/3, Regex.replace/4
```

## Control Flow

### Conditional Expressions
```elixir
# if/else
if condition do
  value1
else
  value2
end

# unless
unless condition do
  value
end

# case
case value do
  pattern1 -> result1
  pattern2 -> result2
  _ -> default
end

# cond
cond do
  condition1 -> result1
  condition2 -> result2
  true -> default
end
```

### Anonymous Functions
```elixir
# Function definition and usage
fn x -> x * 2 end

# With multiple parameters
fn x, y -> x + y end

# Used with Enum functions
Enum.map([1, 2, 3], fn x -> x * 2 end)
```

## Blocked Operations

For security, the following operations are **not allowed**:

### File System Access
- `File` module (all functions)
- `Path` module (all functions)

### System Operations
- `System` module (all functions)
- `:os` module (all functions)
- Process spawning and manipulation

### Code Manipulation
- `Code` module (all functions)
- `Module` module (all functions)
- Dynamic module definition
- Import/require/use statements

### Network Operations
- HTTP requests
- Socket operations
- GenServer operations

### Dangerous Operations
- Assignment operations (for immutability)
- Binary operators (`<<`, `>>`) to prevent memory attacks
- Atom creation (to prevent atom table overflow)

## Error Handling

The Code integration provides detailed error messages for different failure scenarios:

### Validation Errors
```elixir
{:error, "Validation failed: Function File.read!/1 is not allowed"}
{:error, "Validation failed: Expecting only `def run` at the top level"}
{:error, "Validation failed: The parameter list `input, context` is required"}
```

### Runtime Errors
```elixir
{:error, "Runtime error: undefined function"}
{:error, "Key error: key :nonexistent_key not found in %{name: \"Alice\"}"}
{:error, "Function clause error: no matching clause for run/2"}
```

### Parse Errors
```elixir
{:error, "Parse error: syntax error before: ')'"}
```

## Performance Characteristics

### Execution Modes

The Code integration uses dual-mode execution for optimal performance:

1. **Interpreted Mode**: Used internally for validation during development
2. **Compiled Mode**: Used for production execution (default)

### Performance Metrics

- **Validation Time**: Sub-millisecond AST validation
- **Compilation Time**: First execution compiles and caches module
- **Execution Time**: Subsequent executions use cached compiled module
- **Timeout**: 1000ms maximum execution time
- **Memory**: Process-isolated execution with automatic cleanup

## Best Practices

### 1. Function Structure
Always define your code with the exact signature:
```elixir
def run(input, context) do
  # Your logic here
end
```

### 2. Error Handling
Use pattern matching and guards for robust code:
```elixir
def run(input, _context) do
  case input do
    %{"numbers" => numbers} when is_list(numbers) ->
      Enum.sum(numbers)
    %{"numbers" => number} when is_number(number) ->
      number
    _ ->
      {:error, "Invalid input format"}
  end
end
```

### 3. Data Validation
Validate input data early:
```elixir
def run(input, _context) do
  with {:ok, name} <- Map.fetch(input, "name"),
       {:ok, age} <- Map.fetch(input, "age"),
       true <- is_binary(name),
       true <- is_integer(age) and age > 0 do
    "#{name} is #{age} years old"
  else
    _ -> {:error, "Invalid input: expected name (string) and age (positive integer)"}
  end  
end
```

### 4. Using Context
Access workflow data through context:
```elixir
def run(input, context) do
  # Access previous node results
  api_data = context.nodes["api_call"]["response"]
  
  # Access environment variables
  environment = context.env["environment"]
  
  # Access workflow variables
  settings = context.vars["settings"]
  
  # Process data
  %{
    "input" => input,
    "api_data" => api_data,
    "environment" => environment,
    "settings" => settings
  }
end
```

## Integration Architecture

The Code integration consists of several specialized modules:

- **`Prana.Integrations.Code`**: Main integration module
- **`Prana.Integrations.Code.ElixirCodeAction`**: Action implementation
- **`Prana.Integrations.Code.Sandbox`**: Dual-mode execution engine
- **`Prana.Integrations.Code.AstValidator`**: Security validation
- **`Prana.Integrations.Code.SecurityPolicy`**: Whitelist management

This modular design ensures maintainable, secure, and performant code execution within Prana workflows.