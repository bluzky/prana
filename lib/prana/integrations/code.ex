defmodule Prana.Integrations.Code do
  @moduledoc """
  Code Integration for Prana Workflows

  Provides secure execution of user-provided Elixir code within Prana workflows.
  Uses Sequin's proven MiniElixir patterns for security-first sandboxed execution.

  ## Features

  - **Security-first design**: Whitelist-only validation with AST-level security
  - **Dual-mode execution**: Interpreted for validation, compiled for production
  - **Process isolation**: Task-based execution with timeout protection
  - **Context integration**: Access to workflow data and variables
  - **High performance**: Sub-millisecond validation, cached module compilation

  ## Actions

  - `elixir` - Execute Elixir code in a secure sandbox environment

  ## Security Model

  Based on Sequin's proven whitelist-only approach:
  - Only explicitly approved operations are allowed
  - AST validation before any execution
  - Process isolation with timeout limits
  - No dangerous operations (file access, system calls, etc.)
  """

  @behaviour Prana.Behaviour.Integration

  alias Prana.Integration
  alias Prana.Integrations.Code.ElixirCodeAction

  @impl true
  def definition do
    %Integration{
      name: "code",
      display_name: "Code Execution",
      description: "Execute Elixir code in a sandboxed environment with security validation",
      version: "1.0.0",
      category: "development",
      actions: %{
        "elixir" => ElixirCodeAction.specification()
      }
    }
  end
end
