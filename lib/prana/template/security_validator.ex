defmodule Prana.Template.SecurityValidator do
  @moduledoc """
  Centralized security validation for template engine operations.

  Provides consistent security limits and validation across all template operations
  to prevent resource exhaustion and malicious template execution.
  """

  # Security limits - centralized configuration
  @default_limits %{
    # 100KB template size limit
    max_template_size: 100_000,
    # Maximum control structure nesting
    max_nesting_depth: 50,
    # Maximum loop iterations
    max_loop_iterations: 10_000,
    # Maximum expression evaluation recursion
    max_recursion_depth: 100
  }

  @doc """
  Validate template size against security limits.
  """
  @spec validate_template_size(String.t(), map()) :: :ok | {:error, String.t()}
  def validate_template_size(template_string, opts \\ %{}) do
    limits = build_limits(opts)
    template_size = byte_size(template_string)
    max_size = limits.max_template_size

    if template_size > max_size do
      {:error, "Template size (#{template_size} bytes) exceeds maximum allowed limit of #{max_size} bytes"}
    else
      :ok
    end
  end

  @doc """
  Validate control structure nesting depth.
  """
  @spec validate_nesting_depth(non_neg_integer(), map()) :: :ok | {:error, String.t()}
  def validate_nesting_depth(current_depth, opts \\ %{}) do
    limits = build_limits(opts)
    max_depth = limits.max_nesting_depth

    if current_depth >= max_depth do
      {:error, "Control structure nesting depth (#{current_depth}) exceeds maximum allowed limit of #{max_depth}"}
    else
      :ok
    end
  end

  @doc """
  Validate loop iteration count.
  """
  @spec validate_loop_iterations(non_neg_integer(), map()) :: :ok | {:error, String.t()}
  def validate_loop_iterations(iteration_count, opts \\ %{}) do
    limits = build_limits(opts)
    max_iterations = limits.max_loop_iterations

    if iteration_count > max_iterations do
      {:error, "Loop iterations (#{iteration_count}) exceed maximum allowed limit of #{max_iterations}"}
    else
      :ok
    end
  end

  @doc """
  Validate expression evaluation recursion depth.
  """
  @spec validate_recursion_depth(non_neg_integer(), map()) :: :ok | {:error, String.t()}
  def validate_recursion_depth(current_depth, opts \\ %{}) do
    limits = build_limits(opts)
    max_depth = limits.max_recursion_depth

    if current_depth > max_depth do
      {:error, "Expression recursion depth (#{current_depth}) exceeds maximum allowed limit of #{max_depth}"}
    else
      :ok
    end
  end

  @doc """
  Get current security limits (for testing and introspection).
  """
  @spec get_limits(map()) :: map()
  def get_limits(opts \\ %{}) do
    build_limits(opts)
  end

  # Private functions

  defp build_limits(opts) do
    Map.merge(@default_limits, opts)
  end
end
