defmodule Prana.Behaviour.ExpressionEngine do
  @moduledoc """
  Behavior for expression evaluation engines.
  Allows pluggable expression languages and evaluation strategies.
  """

  @type expression :: String.t()
  @type context :: map()
  @type compiled_expression :: any()

  @doc """
  Evaluate an expression with the given context
  """
  @callback evaluate(expression(), context()) :: {:ok, any()} | {:error, reason :: any()}

  @doc """
  Compile an expression for repeated evaluation (optional optimization)
  """
  @callback compile(expression()) :: {:ok, compiled_expression()} | {:error, reason :: any()}

  @doc """
  Evaluate a pre-compiled expression
  """
  @callback evaluate_compiled(compiled_expression(), context()) :: {:ok, any()} | {:error, reason :: any()}

  @doc """
  Validate expression syntax without evaluation
  """
  @callback validate_syntax(expression()) :: :ok | {:error, reason :: any()}

  @doc """
  Extract variables referenced in an expression
  """
  @callback extract_variables(expression()) :: {:ok, [String.t()]} | {:error, reason :: any()}

  @optional_callbacks [compile: 1, evaluate_compiled: 2, extract_variables: 1]
end
