defmodule Prana.Template.AST do
  @moduledoc """
  AST helper functions and utilities for template expressions.
  Follows Elixir's 3-tuple AST pattern: {type, [], children}
  """
  
  @doc "Create a literal AST node"
  def literal(value) do
    {:literal, [], [value]}
  end
  
  @doc "Create a variable AST node"
  def variable(path) do
    {:variable, [], [path]}
  end
  
  @doc "Create a binary operation AST node"
  def binary_op(operator, left, right) do
    {:binary_op, [], [operator, left, right]}
  end
  
  @doc "Create a function call AST node"
  def call(function, args) do
    {:call, [], [function, args]}
  end
  
  @doc "Create a pipe operation AST node"
  def pipe(expression, function) do
    {:pipe, [], [expression, function]}
  end
  
  @doc "Create a grouped expression AST node"
  def grouped(expression) do
    {:grouped, [], [expression]}
  end
  
  @doc "Extract children from AST node"  
  def children({_type, [], children}), do: children
  
  @doc "Extract type from AST node"
  def type({type, [], _children}), do: type
end