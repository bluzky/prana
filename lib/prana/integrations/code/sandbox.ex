defmodule Prana.Integrations.Code.Sandbox do
  @moduledoc """
  Secure Elixir code sandbox with dual-mode execution.

  Provides two simple APIs for executing user-provided Elixir code safely:

  ## API

  - `run_interpreted/2` - For validation and development (slower, safer)
  - `run_compiled/3` - For production execution (faster, cached modules)

  Both methods take code as a string and expect a `def run(input, context)` function.

  ## Security

  Uses Sequin's proven whitelist-based AST validation to prevent dangerous operations
  while allowing safe data processing, control flow, and standard library functions.

  ## Context Handling

  Context is passed fresh to each execution, preventing stale data issues.
  Both modes produce identical results for the same input.

  ## Examples

      # Development/validation
      Sandbox.run_interpreted("def run(input, _ctx), do: input.name", context)

      # Production execution
      Sandbox.run_compiled("def run(input, _ctx), do: input.name", "node_123", context)
  """

  alias Prana.Integrations.Code.AstValidator
  require Logger

  # Sequin uses 1000ms timeout
  @timeout 1000

  @doc """
  Execute code in interpreted mode for validation and development.

  Takes code string and context, returns execution result.
  Safer but slower execution mode using Code.eval_quoted_with_env.

  ## Parameters
  - `code` - String containing Elixir code with `def run(input, context)` function
  - `context` - Prana workflow context map

  ## Returns
  - `{:ok, result}` - Successful execution
  - `{:error, reason}` - Validation or execution error
  """
  def run_interpreted(code, context) when is_binary(code) do
    case Code.string_to_quoted(code) do
      {:ok, ast} -> run_interpreted_ast(ast, context)
      {:error, reason} -> {:error, "Parse error: #{inspect(reason)}"}
    end
  end

  # Internal function that works with AST
  defp run_interpreted_ast(ast, context) do
    task =
      Task.async(fn ->
        try do
          # Validate AST and extract function body using our security validator
          case AstValidator.check(ast) do
            {:ok, body_ast} ->
              # Create bindings from Prana context
              bindings = create_bindings(context)

              # Create binding list that matches run_compiled function signature:
              # def run(input, context) - so we need 'input' and 'context' variables
              binding_list = [
                input: context["$input"] || %{},
                context: bindings
              ]

              # Evaluate just the function body with the right bindings
              {result, _new_bindings, _env} =
                Code.eval_quoted_with_env(
                  body_ast,
                  binding_list,
                  __ENV__
                )

              {:ok, result}

            {:error, reason} ->
              {:error, "Validation failed: #{reason}"}
          end
        rescue
          error ->
            Logger.error(inspect(__STACKTRACE__))
            encode_error(error)
        end
      end)

    Task.await(task, @timeout)
  end

  @doc """
  Execute code in compiled mode for production execution.

  Takes code string, unique identifier, and context, returns execution result.
  Faster execution using dynamically compiled modules.

  ## Parameters
  - `code` - String containing Elixir code with `def run(input, context)` function
  - `code_id` - Unique identifier for module caching (e.g., "workflow_id_node_key")
  - `context` - Prana workflow context map

  ## Returns
  - `{:ok, result}` - Successful execution
  - `{:error, reason}` - Validation or execution error
  """
  def run_compiled(code, code_id, context) when is_binary(code) do
    case Code.string_to_quoted(code) do
      {:ok, ast} -> run_compiled_ast(code_id, ast, context)
      {:error, reason} -> {:error, "Parse error: #{inspect(reason)}"}
    end
  end

  # Internal function that works with AST
  defp run_compiled_ast(code_id, ast, context) do
    task =
      Task.async(fn ->
        try do
          # Generate unique module name using node_key and execution_id
          module_name = generate_module_name(code_id)

          # Validate AST first - use same validation as interpreted mode
          case AstValidator.validate_ast(ast) do
            :ok ->
              # Ensure module is loaded (Sequin's pattern)
              ensure_code_is_loaded(module_name, ast, context)

              # Call the compiled module's run function with input and context parameters
              bindings = create_bindings(context)
              result = apply(module_name, :run, [context["$input"] || %{}, bindings])

              {:ok, result}

            {:error, reason} ->
              {:error, "Validation failed: #{reason}"}
          end
        rescue
          error ->
            Logger.error(inspect(__STACKTRACE__))
            encode_error(error)
        end
      end)

    Task.await(task, @timeout)
  end

  # Generate unique module name using node key and execution ID.
  # Adapted from Sequin's pattern: "UserFunction.{id}"
  # Our pattern: "PranaUserCode.NodeKey_ExecutionId"
  defp generate_module_name(code_id) do
    # Create safe module name from node_key and execution_id
    safe_code_id = String.replace(to_string(code_id), ~r/[^a-zA-Z0-9_]/, "_")

    :"Elixir.PranaUserCode.#{safe_code_id}"
  end

  # Ensure code is loaded (Sequin's ensure_code_is_loaded pattern).
  # Checks if module exists, compiles if needed.
  # Context is not needed for compilation - only for runtime execution.
  defp ensure_code_is_loaded(module_name, ast, _context) do
    if Code.loaded?(module_name) do
        :ok
      else
        compile_and_load(module_name, ast)
    end
  end

  # Compile and load dynamic module (Sequin's compile_and_load pattern).
  defp compile_and_load(module_name, ast) do
    module_ast = create_module_ast(module_name, ast)

    # Compile and load with :code.load_binary (Sequin's approach)
    [{^module_name, bytecode}] = Code.compile_quoted(module_ast)
    :code.load_binary(module_name, ~c"#{module_name}.beam", bytecode)
  end

  # Create module AST (Sequin's create_expr pattern).
  # User provides complete function definition, we just wrap it in a module.
  # No context baking - the function accepts fresh context at each call.
  defp create_module_ast(module_name, user_function_ast) do
    quote do
      defmodule unquote(module_name) do
        unquote(user_function_ast)
      end
    end
  end

  # Create bindings for Prana context (adapted from Sequin's pattern).
  # Sequin uses: action, record, changes, metadata
  # We use: input, nodes, vars, env
  defp create_bindings(context) do
    %{
      nodes: context["$nodes"] || %{},
      vars: context["$vars"] || %{},
      env: context["$env"] || %{},
      execution: context["$execution"] || %{}
    }
  end

  # Encode error (Sequin's error encoding pattern).
  # Provides structured error information for debugging.
  defp encode_error(error) do
    case error do
      %CompileError{description: description, line: line} ->
        {:error, "Compile error at line #{line}: #{description}"}

      %SyntaxError{description: description, line: line} ->
        {:error, "Syntax error at line #{line}: #{description}"}

      %RuntimeError{message: message} ->
        {:error, "Runtime error: #{message}"}

      %KeyError{key: key, term: term} ->
        {:error, "Key error: key #{inspect(key)} not found in #{inspect(term)}"}

      %FunctionClauseError{function: function, arity: arity} ->
        {:error, "Function clause error: no matching clause for #{function}/#{arity}"}

      %ArgumentError{message: message} ->
        {:error, "Argument error: #{message}"}

      %UndefinedFunctionError{function: function, arity: arity, module: module} ->
        {:error, "Undefined function: #{module}.#{function}/#{arity}"}

      %MatchError{term: term} ->
        {:error, "Match error: no match of right hand side value: #{inspect(term)}"}

      # Generic error handling for unexpected error types
      error when is_exception(error) ->
        {:error, "#{error.__struct__}: #{Exception.message(error)}"}

      # Non-exception errors
      error ->
        {:error, "Unexpected error: #{inspect(error)}"}
    end
  end
end
