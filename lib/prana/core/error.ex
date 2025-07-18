defmodule Prana.Core.Error do
  @moduledoc """
  Standardized error structure for consistent error handling across Prana.

  This module provides a common error structure with:
  - `code`: String error code for programmatic handling
  - `message`: Human-readable error description  
  - `details`: Optional map with additional error context

  ## Examples

      iex> %Prana.Core.Error{code: "validation_failed", message: "Invalid input"}
      %Prana.Core.Error{code: "validation_failed", message: "Invalid input", details: nil}

      iex> Prana.Core.Error.new("not_found", "Resource not found", %{resource_id: 123})
      %Prana.Core.Error{code: "not_found", message: "Resource not found", details: %{resource_id: 123}}
  """

  @type t :: %__MODULE__{
          code: String.t(),
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

  ## Parameters
  - `code`: Error code for programmatic handling
  - `message`: Human-readable error description
  - `details`: Optional map with additional context (defaults to nil)

  ## Examples

      iex> Prana.Core.Error.new("config_error", "Invalid configuration")
      %Prana.Core.Error{code: "config_error", message: "Invalid configuration", details: nil}

      iex> Prana.Core.Error.new("http_error", "Request failed", %{status_code: 404})
      %Prana.Core.Error{code: "http_error", message: "Request failed", details: %{status_code: 404}}
  """
  @spec new(String.t(), String.t(), map() | nil) :: t()
  def new(code, message, details \\ nil) do
    %__MODULE__{
      code: code,
      message: message,
      details: details
    }
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
end