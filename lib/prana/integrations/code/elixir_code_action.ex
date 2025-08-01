defmodule Prana.Integrations.Code.ElixirCodeAction do
  @moduledoc """
  Elixir Code Execution Action for Prana

  Executes user-provided Elixir code in a secure sandbox environment.
  Uses Sequin's dual-mode execution pattern adapted for Prana workflows:

  - Development mode (:interpreted): Safe validation using Code.eval_quoted_with_env
  - Production mode (:compiled): Fast execution using dynamically compiled modules
  """

  use Prana.Actions.SimpleAction

  alias Prana.Action
  alias Prana.Integrations.Code.Sandbox

  def specification do
    %Action{
      name: "code.elixir",
      display_name: "Execute Elixir Code",
      description: "Execute Elixir code in a sandboxed environment with security validation",
      type: :action,
      module: __MODULE__,
      input_ports: ["main"],
      output_ports: ["main", "error"]
    }
  end

  @impl true
  def execute(params, context) do
    # Extract parameters
    code = params["code"]

    # Get node context for unique module naming
    code_identifier = get_code_id(context)

    # Validate required parameters
    case validate_code_param(code) do
      :ok ->
        # Always use compiled mode for execution (Sequin's production pattern)
        case Sandbox.run_compiled(code, code_identifier, context) do
          {:ok, result} ->
            {:ok, %{result: result}}

          {:error, error} ->
            {:error, format_error(error)}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Extract node key from context (fallback to random if not available)
  defp get_code_id(context) do
    "#{context["$workflow"]["id"]}_#{context["$execution"]["current_node_key"]}"
  end

  # Validate required parameters
  defp validate_code_param(code) do
    cond do
      is_nil(code) or code == "" ->
        {:error, "Code parameter is required"}

      not is_binary(code) ->
        {:error, "Code must be a string"}

      true ->
        :ok
    end
  end

  # Format error for consistent output
  defp format_error(error) when is_binary(error), do: error
  defp format_error(%{message: message}), do: message
  defp format_error(%{type: type, message: message}), do: "#{type}: #{message}"
  defp format_error(error), do: inspect(error)

  @doc """
  Returns parameter schema for this action.

  Defines the expected parameters and their validation rules.
  """
  @impl true
  def params_schema do
    %{
      "code" => %{
        "type" => "string",
        "required" => true,
        "description" => "Elixir code to execute"
      }
    }
  end

  @doc """
  Validates parameters according to schema.
  """
  @impl true
  def validate_params(params) do
    schema = params_schema()
    errors = []

    # Validate code parameter
    errors =
      if schema["code"]["required"] and is_nil(params["code"]) do
        ["Code parameter is required" | errors]
      else
        errors
      end

    errors =
      if params["code"] && !is_binary(params["code"]) do
        ["Code must be a string" | errors]
      else
        errors
      end

    case errors do
      [] -> {:ok, params}
      errors -> {:error, errors}
    end
  end
end
