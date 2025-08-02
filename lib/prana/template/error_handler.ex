defmodule Prana.Template.ErrorHandler do
  @moduledoc """
  Centralized error handling and transformation for template engine operations.

  Provides consistent error message formatting and graceful error handling
  strategies across all template operations.
  """

  @doc """
  Handle and transform template parsing errors consistently.
  """
  @spec handle_parse_error(any()) :: {:error, String.t()}
  def handle_parse_error(error_reason) do
    case error_reason do
      {:error, message} when is_binary(message) ->
        {:error, message}

      {:error, reason} ->
        {:error, "Template parsing failed: #{inspect(reason)}"}

      error when is_binary(error) ->
        {:error, "Template parsing failed: #{error}"}

      error ->
        {:error, "Template parsing failed: #{inspect(error)}"}
    end
  end

  @doc """
  Handle and transform expression evaluation errors consistently.
  """
  @spec handle_evaluation_error(any()) :: {:error, String.t()}
  def handle_evaluation_error(error_reason) do
    case error_reason do
      {:error, message} when is_binary(message) ->
        {:error, message}

      {:max_recursion, depth} ->
        {:error, "Maximum recursion depth exceeded at depth #{depth}"}

      {:error, reason} ->
        {:error, "Expression evaluation failed: #{inspect(reason)}"}

      error when is_binary(error) ->
        {:error, "Expression evaluation failed: #{error}"}

      error ->
        {:error, "Expression evaluation failed: #{inspect(error)}"}
    end
  end

  @doc """
  Handle and transform control flow evaluation errors consistently.
  """
  @spec handle_control_error(any()) :: {:error, String.t()}
  def handle_control_error(error_reason) do
    case error_reason do
      {:error, message} when is_binary(message) ->
        {:error, message}

      {:error, reason} ->
        {:error, "Control block evaluation failed: #{inspect(reason)}"}

      error when is_binary(error) ->
        {:error, "Control block evaluation failed: #{error}"}

      error ->
        {:error, "Control block evaluation failed: #{inspect(error)}"}
    end
  end

  @doc """
  Handle security limit violations (always return errors, never graceful).
  """
  @spec handle_security_error(String.t()) :: {:error, String.t()}
  def handle_security_error(message) when is_binary(message) do
    {:error, message}
  end

  @doc """
  Apply graceful error handling mode if configured.

  In graceful mode, certain errors return fallback values instead of errors.
  Security errors are never handled gracefully.
  """
  @spec apply_graceful_mode({:error, String.t()}, String.t(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def apply_graceful_mode({:error, message}, fallback_value, opts \\ %{}) do
    if is_graceful_mode?(opts) and not is_always_error?(message) do
      {:ok, fallback_value}
    else
      {:error, message}
    end
  end

  # Private functions

  defp is_graceful_mode?(opts) do
    not Map.get(opts, :strict_mode, false)
  end

  defp is_security_error?(message) when is_binary(message) do
    String.contains?(message, "exceeds maximum") or
      String.contains?(message, "security") or
      String.contains?(message, "limit")
  end

  @doc """
  Check if an error should never be handled gracefully (always return error).

  Filter errors and function errors should always return errors, even in graceful mode.
  """
  @spec is_always_error?(String.t()) :: boolean()
  def is_always_error?(message) when is_binary(message) do
    is_security_error?(message) or
      String.contains?(message, "Unknown filter") or
      String.contains?(message, "Filter application failed") or
      String.contains?(message, "Filter error")
  end
end
