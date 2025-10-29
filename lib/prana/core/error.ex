defmodule Prana.Core.Error do
  @moduledoc false
  @type t :: %__MODULE__{
          code: atom(),
          message: String.t(),
          details: map() | nil
        }

  defstruct [
    :code,
    :message,
    :details
  ]

  @doc """
  Creates a new error struct.

  ## Overloads

  ### new(code, message, details \\ nil)
  Creates an error with custom code, message and optional details.

  #### Parameters
  - `code`: Error code for programmatic handling
  - `message`: Human-readable error description
  - `details`: Optional map with additional context (defaults to nil)

  #### Examples
      iex> Foundation.Error.new("config_error", "Invalid configuration")
      %Foundation.Error{code: "config_error", message: "Invalid configuration", details: nil}

      iex> Foundation.Error.new("http_error", "Request failed", %{status_code: 404})
      %Foundation.Error{code: "http_error", message: "Request failed", details: %{status_code: 404}}

  ### new(skema_result)
  Creates an invalid_params error from a Skema.Result.

  Extracts schema validation errors from the Skema.Result and formats them into a
  structured error details map for consistent error handling.

  #### Parameters
  - `result`: A Skema.Result with validation errors

  #### Returns
  A Foundation.Error with:
  - `code`: `:invalid_params`
  - `message`: "Schema validation failed"
  - `details`: Map containing formatted validation errors

  #### Examples
      iex> result = %Skema.Result{errors: %{email: "is required", age: "must be a number"}}
      iex> Foundation.Error.new(result)
      %Foundation.Error{
        code: :invalid_params,
        message: "Schema validation failed",
        details: %{errors: %{email: "is required", age: "must be a number"}}
      }

      iex> result = %Skema.Result{errors: %{user: %{name: "is required", email: ["is required", "must be valid"]}}}
      iex> Foundation.Error.new(result)
      %Foundation.Error{
        code: :invalid_params,
        message: "Schema validation failed",
        details: %{errors: %{user: %{name: "is required", email: ["is required", "must be valid"]}}}
      }
  """
  @spec new(String.t(), String.t(), map() | nil) :: t()
  def new(code, message, details \\ nil)

  def new(code, message, details) do
    %__MODULE__{
      code: code,
      message: message,
      details: details
    }
  end

  @spec new(Skema.Result.t()) :: t()
  def new(%Skema.Result{} = result) do
    formatted_errors = format_skema_errors(result)

    %__MODULE__{
      code: :invalid_params,
      message: "Schema validation failed",
      details: %{errors: formatted_errors}
    }
  end

  def new(%__MODULE__{} = result), do: result

  def new(%{errors: errors}) when is_map(errors) do
    %__MODULE__{
      code: :invalid_params,
      message: "validation failed",
      details: errors
    }
  end

  @doc false
  defp format_skema_errors(%Skema.Result{errors: errors}) do
    format_skema_errors(errors)
  end

  defp format_skema_errors(errors) when is_map(errors) do
    Map.new(errors, fn {key, value} -> {key, format_skema_errors(value)} end)
  end

  defp format_skema_errors(errors) when is_list(errors) do
    Enum.map(errors, &format_skema_errors/1)
  end

  defp format_skema_errors(error), do: error

  @error_types [
    :not_found,
    :invalid_params,
    :unprocessable,
    :system_error,
    :unauthorized,
    :forbidden,
    :service_error,
    :api_gateway_error,
    :engine_error,
    :workflow_error
  ]

  @doc """
  Auto-generated helper functions for common error types.

  The following functions are dynamically generated for each error type in @error_types:

  - `not_found/2` - Creates a not_found error
  - `invalid_params/2` - Creates an invalid_params error
  - `system_error/2` - Creates a system_error error
  - `unprocessable/2` - Creates an unprocessable error
  - `unauthorized/2` - Creates an unauthorized error
  - `forbidden/2` - Creates a forbidden error

  Each function accepts:
  - `message` (String.t()) - Human-readable error description
  - `details` (map() | nil, optional) - Additional error context

  ## Examples

      iex> Foundation.Error.not_found("User not found")
      %Foundation.Error{code: :not_found, message: "User not found", details: nil}

      iex> Foundation.Error.invalid_params("Missing required field", %{field: "email"})
      %Foundation.Error{code: :invalid_params, message: "Missing required field", details: %{field: "email"}}

      iex> Foundation.Error.system_error("Database connection failed", %{timeout: 5000})
      %Foundation.Error{code: :system_error, message: "Database connection failed", details: %{timeout: 5000}}
  """
  for error_type <- @error_types do
    def unquote(error_type)(message, details \\ nil) do
      new(unquote(error_type), message, details)
    end
  end

  @doc """
  Creates an action error with specific error type preserved in details.
  This helps maintain backwards compatibility while standardizing the structure.

  ## Parameters
  - `error_type`: Specific error type (e.g., "config_error", "http_error")
  - `message`: Human-readable error description
  - `extra_details`: Optional map with additional context

  ## Examples

      iex> Prana.Core.Error.action_error("config_error", "Invalid mode")
      %Prana.Core.Error{code: "action_error", message: "Invalid mode", details: %{"error_type" => "config_error"}}

      iex> Prana.Core.Error.action_error("http_error", "Request failed", %{status_code: 404})
      %Prana.Core.Error{code: "action_error", message: "Request failed", details: %{"error_type" => "http_error", status_code: 404}}
  """
  @spec action_error(String.t(), String.t(), map()) :: t()
  def action_error(error_type, message, extra_details \\ %{}) do
    details = Map.merge(%{"error_type" => error_type}, extra_details)
    new("action_error", message, details)
  end

  def to_map(%__MODULE__{} = error) do
    %{
      code: error.code,
      message: error.message,
      details: Nested.to_map(error.details)
    }
  end
end
