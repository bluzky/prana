defmodule Prana.Actions.SimpleAction do
  @moduledoc """
  Default implementation for simple actions that only need execute/2.

  This module provides a base implementation for actions that:
  - Don't need preparation phase (prepare/2 returns empty map)
  - Don't support suspension/resume (resume/2 returns error)
  - Only need basic execute/2 functionality

  ## Usage

  Use this as a base for simple actions by defining only the execute/2 callback:

      defmodule MyApp.SimpleHttpAction do
        use Prana.Actions.SimpleAction

        def execute(params, _context) do
          # Simple HTTP request logic
          case HTTPoison.get(params["url"]) do
            {:ok, %{status_code: 200, body: body}} ->
              {:ok, %{response: body}}
            {:error, reason} ->
              {:error, reason}
          end
        end
      end

  ## Behavior Implementation

  - `prepare/2` - Returns `{:ok, %{}}` (no preparation needed)
  - `execute/2` - Must be implemented by using module
  - `resume/2` - Returns `{:error, "Resume not supported"}`
  - `suspendable?/0` - Returns `false`

  ## When to Use

  Use SimpleAction when:
  - Action doesn't need dynamic configuration from execution context
  - Action doesn't need to suspend/resume execution
  - Action logic is self-contained and stateless
  - Action configuration is static and provided in action_config

  ## When NOT to Use

  Don't use SimpleAction when:
  - Action needs access to execution context variables or node data
  - Action needs to suspend execution and wait for external events
  - Action needs complex preparation or setup logic
  - Action configuration depends on runtime context
  """

  defmacro __using__(_opts) do
    quote do
      use Prana.Behaviour.Action

      @doc """
      Default preparation - returns empty map.

      Simple actions don't need preparation, so this returns an empty map.
      Override this method if your action needs preparation logic.
      """
      def prepare(_node) do
        {:ok, nil}
      end

      @doc """
      Resume not supported for simple actions.

      Simple actions don't support suspension/resume. Override this method
      if your action needs to support resumption.
      """
      def resume(_params, _context, _resume_data) do
        {:error, "Resume not supported"}
      end

      @doc """
      Simple actions are not suspendable by default.
      """
      def suspendable?, do: false

      # Allow overriding prepare/1 and resume/3 for more complex simple actions
      defoverridable prepare: 1, resume: 3, suspendable?: 0
    end
  end

  @doc """
  Helper function to create a simple action module dynamically.

  This is useful for creating simple actions without defining a full module.
  The action will use the provided function for execution.

  ## Parameters
  - `execute_fn` - Function with arity 2 that takes (params, preparation_data)

  ## Returns
  A module that implements the Action behavior with the provided execute function.

  ## Example

      action_module = SimpleAction.create(fn params, _prep_data ->
        {:ok, %{result: params["value"] * 2}}
      end)

      # Can be used in action definitions
      %Prana.Action{
        name: "double_value",
        module: action_module,
        # ... other fields
      }
  """
  def create(execute_fn) when is_function(execute_fn, 2) do
    Module.create(
      :"Elixir.Prana.Actions.Dynamic.SimpleAction#{:erlang.unique_integer([:positive])}",
      quote do
        use Prana.Actions.SimpleAction

        def execute(params, preparation_data) do
          unquote(execute_fn).(params, preparation_data)
        end
      end,
      Macro.Env.location(__ENV__)
    )
  end
end
