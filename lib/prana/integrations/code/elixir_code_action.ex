defmodule Prana.Integrations.Code.ElixirCodeAction do
  @moduledoc """
  Elixir Code Execution Action for Prana

  Executes user-provided Elixir code in a secure sandbox environment with security validation.
  Uses compiled execution mode for optimal performance and safety, adapted from Sequin's execution patterns.

  ## Parameters
  - `code` (required): Elixir code string to execute in the sandbox

  ## Code Requirements
  Custom code must define a `run/2` function with the signature:
  ```elixir
  def run(input, context)
  ```

  ## Example Params JSON
  ```json
  {
    "code": "def run(input, context) do\n  user_count = length(input[:users] || [])\n  age_sum = Enum.reduce(input[:users] || [], 0, fn user, acc -> acc + (user[:age] || 0) end)\n  avg_age = if user_count > 0, do: age_sum / user_count, else: 0\n\n  %{\n    user_count: user_count,\n    average_age: avg_age,\n    processed_at: DateTime.utc_now() |> DateTime.to_iso8601()\n  }\nend"
  }
  ```

  ## Function Parameters
  The `run/2` function receives:
  - `input`: The input data from the workflow node
  - `context`: Full workflow execution context including nodes, variables, and execution state

  ## Security Features
  - Sandboxed execution environment
  - Limited module access for security
  - Timeout protection
  - Memory limits
  - No file system or network access

  ## Output Ports
  - `main`: Code executed successfully with result
  - `error`: Code execution errors or validation failures

  ## Output Format
  Returns the result of the last expression in the provided code.
  The result should be a JSON-serializable data structure.

  ## Example Code Patterns

  ### Data Transformation
  ```elixir
  def run(input, context) do
    users = input[:users] || []
    processed_users = Enum.map(users, fn user ->
      %{
        id: user[:id],
        name: String.upcase(user[:name] || ""),
        age_group: if user[:age] >= 18, do: "adult", else: "minor"
      }
    end)

    %{users: processed_users, count: length(processed_users)}
  end
  ```

  ### Using Context Data
  ```elixir
  def run(input, context) do
    workflow_id = context[:workflow][:id]
    execution_id = context[:execution][:id]
    previous_node_data = context[:nodes][:previous_step][:output]

    %{
      result: input[:value] * 2,
      metadata: %{
        workflow_id: workflow_id,
        execution_id: execution_id,
        previous_result: previous_node_data
      }
    }
  end
  ```

  ### Conditional Logic
  ```elixir
  def run(input, context) do
    score = input[:score] || 0

    grade = cond do
      score >= 90 -> "A"
      score >= 80 -> "B"
      score >= 70 -> "C"
      score >= 60 -> "D"
      true -> "F"
    end

    %{grade: grade, passed: score >= 60}
  end
  ```
  """

  use Prana.Actions.SimpleAction

  alias Prana.Action
  alias Prana.Core.Error
  alias Prana.Integrations.Code.Sandbox

  def definition do
    %Action{
      name: "code.elixir",
      display_name: "Execute Elixir Code",
      description: @moduledoc,
      type: :action,
      input_ports: ["main"],
      output_ports: ["main"],
      params_schema: %{
        code: [
          type: :string,
          description: "Elixir code string to execute in the sandbox. Must define a run/2 function.",
          required: true
        ]
      }
    }
  end

  @impl true
  def execute(params, context) do
    # Validate required code parameter
    # Get node context for unique module naming
    code_identifier = get_code_id(context)

    # Always use compiled mode for execution (Sequin's production pattern)
    case Sandbox.run_compiled(params.code, code_identifier, context) do
      {:ok, result} ->
        {:ok, result}

      {:error, error} ->
        {:error, Error.new("execution_error", "Execution failed", format_error(error))}
    end
  end

  # Extract node key from context
  defp get_code_id(context) do
    "#{context["$workflow"]["id"]}_#{context["$execution"]["current_node_key"]}"
  end

  # Format error for consistent output - always returns a string
  defp format_error(error) when is_binary(error), do: error
  defp format_error(%{"message" => message}), do: message
  defp format_error(%{message: message}), do: message
  defp format_error(%{"type" => type, "message" => message}), do: "#{type}: #{message}"
  defp format_error(%{type: type, message: message}), do: "#{type}: #{message}"
  defp format_error(error), do: inspect(error)
end
