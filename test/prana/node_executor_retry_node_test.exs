defmodule Prana.NodeExecutorRetryNodeTest do
  use ExUnit.Case, async: false

  alias Prana.Actions.SimpleAction
  alias Prana.Core.Error
  alias Prana.IntegrationRegistry
  alias Prana.Node
  alias Prana.NodeExecution
  alias Prana.NodeExecutor
  alias Prana.NodeSettings
  alias Prana.WorkflowExecution

  # Test actions for retry_node testing
  defmodule SuccessAfterRetryAction do
    @moduledoc false
    use SimpleAction

    alias Prana.Action

    def definition do
      %Action{
        name: "test.success_after_retry",
        display_name: "Success After Retry",
        description: "Fails once then succeeds on retry",
        type: :action,
        module: __MODULE__,
        input_ports: ["main"],
        output_ports: ["main"]
      }
    end

    @impl true
    def execute(_params, context) do
      # Check if this is a retry by looking for retry attempt in context
      retry_attempt = get_in(context, ["$execution", "state", "retry_count"]) || 0

      if retry_attempt == 0 do
        # First attempt - fail
        {:error, "First attempt fails"}
      else
        # Retry attempt - succeed
        {:ok, %{message: "Success on retry", attempt: retry_attempt}}
      end
    end
  end

  defmodule AlwaysFailAction do
    @moduledoc false
    use SimpleAction

    alias Prana.Action

    def definition do
      %Action{
        name: "test.always_fail",
        display_name: "Always Fail",
        description: "Always fails for max retry testing",
        type: :action,
        module: __MODULE__,
        input_ports: ["main"],
        output_ports: ["main"]
      }
    end

    @impl true
    def execute(_params, _context) do
      {:error, "Always fails"}
    end
  end

  defmodule TestIntegration do
    @moduledoc false
    @behaviour Prana.Behaviour.Integration

    def definition do
      %Prana.Integration{
        name: "test",
        display_name: "Test Integration",
        actions: [
          SuccessAfterRetryAction,
          AlwaysFailAction
        ]
      }
    end
  end

  setup do
    # Start IntegrationRegistry
    {:ok, registry_pid} = IntegrationRegistry.start_link()

    # Register test integration
    IntegrationRegistry.register_integration(TestIntegration)

    # Create a minimal execution graph for testing
    execution_graph = %Prana.ExecutionGraph{
      workflow_id: "test_workflow",
      trigger_node_key: "trigger",
      dependency_graph: %{},
      connection_map: %{},
      reverse_connection_map: %{},
      node_map: %{},
      variables: %{}
    }

    # Create test execution (matching pattern from other tests)
    execution = %WorkflowExecution{
      id: "test_execution",
      workflow_id: "test_workflow",
      workflow_version: 1,
      execution_mode: :async,
      status: "running",
      vars: %{},
      node_executions: %{},
      execution_graph: execution_graph,
      __runtime: %{
        "nodes" => %{},
        "env" => %{"environment" => "test"},
        "active_paths" => %{},
        "executed_nodes" => []
      },
      execution_data: %{
        "context_data" => %{
          "workflow" => %{},
          "node" => %{}
        },
        "active_paths" => %{},
        "active_nodes" => %{}
      }
    }

    # Clean up registry on exit
    on_exit(fn ->
      if Process.alive?(registry_pid) do
        GenServer.stop(registry_pid)
      end
    end)

    {:ok, execution: execution}
  end

  describe "retry_node/4 basic functionality" do
    test "retry_node rebuilds input and calls action.execute", %{execution: execution} do
      # Create a node with retry settings
      settings = NodeSettings.new(%{retry_on_failed: true, max_retries: 2})
      node = Node.new("Retry Test", "test.success_after_retry")
      node = %{node | settings: settings}

      # Create a failed node execution (simulating previous failure)
      failed_node_execution = NodeExecution.new(node.key, 1, 0)
      failed_node_execution = NodeExecution.start(failed_node_execution)

      failed_node_execution =
        NodeExecution.suspend(failed_node_execution, :retry, %{
          "attempt_number" => 1,
          "max_attempts" => 2,
          "resume_at" => DateTime.add(DateTime.utc_now(), 1000, :millisecond),
          "original_error" => "First attempt fails"
        })

      # Update execution state to simulate retry context
      execution = %{execution | execution_data: %{"context_data" => %{"workflow" => %{"retry_count" => 1}}}}

      # Call retry_node
      result =
        NodeExecutor.retry_node(node, execution, failed_node_execution, %{
          execution_index: 2,
          run_index: 0
        })

      # Should succeed on retry
      assert {:ok, completed_node_execution, _updated_execution} = result
      assert completed_node_execution.status == "completed"
      assert completed_node_execution.output_data == %{message: "Success on retry", attempt: 1}
    end

    test "retry_node preserves run_index from original execution", %{execution: execution} do
      settings = NodeSettings.new(%{retry_on_failed: true, max_retries: 2})
      node = Node.new("Run Index Test", "test.success_after_retry")
      node = %{node | settings: settings}

      # Create failed node execution with specific run_index
      original_run_index = 5
      failed_node_execution = NodeExecution.new(node.key, 1, original_run_index)
      failed_node_execution = NodeExecution.start(failed_node_execution)

      failed_node_execution =
        NodeExecution.suspend(failed_node_execution, :retry, %{
          "attempt_number" => 1,
          "max_attempts" => 2
        })

      execution = %{execution | execution_data: %{"context_data" => %{"workflow" => %{"retry_count" => 1}}}}

      result =
        NodeExecutor.retry_node(node, execution, failed_node_execution, %{
          execution_index: 2,
          run_index: original_run_index
        })

      assert {:ok, completed_node_execution, _} = result
      assert completed_node_execution.run_index == original_run_index
    end

    test "retry_node can still fail and trigger another retry", %{execution: execution} do
      settings = NodeSettings.new(%{retry_on_failed: true, max_retries: 3})
      node = Node.new("Multiple Retry", "test.always_fail")
      node = %{node | settings: settings}

      # Create failed node execution from first attempt
      failed_node_execution = NodeExecution.new(node.key, 1, 0)
      failed_node_execution = NodeExecution.start(failed_node_execution)

      failed_node_execution =
        NodeExecution.suspend(failed_node_execution, :retry, %{
          "attempt_number" => 1,
          "max_attempts" => 3,
          "resume_at" => DateTime.add(DateTime.utc_now(), 1000, :millisecond),
          "original_error" =>
            Error.new("action_error", "Action returned error", %{"error" => "Always fails", "port" => "error"})
        })

      result =
        NodeExecutor.retry_node(node, execution, failed_node_execution, %{
          execution_index: 2,
          run_index: 0
        })

      # Should return another retry suspension (attempt 2)
      assert {:suspend, suspended_node_execution} = result
      assert suspended_node_execution.suspension_type == :retry
      assert suspended_node_execution.suspension_data["attempt_number"] == 2
      assert suspended_node_execution.suspension_data["max_attempts"] == 3
    end

    test "retry_node fails when max retries reached", %{execution: execution} do
      settings = NodeSettings.new(%{retry_on_failed: true, max_retries: 2})
      node = Node.new("Max Retry Test", "test.always_fail")
      node = %{node | settings: settings}

      # Create failed node execution at max attempts
      failed_node_execution = NodeExecution.new(node.key, 1, 0)
      failed_node_execution = NodeExecution.start(failed_node_execution)

      failed_node_execution =
        NodeExecution.suspend(failed_node_execution, :retry, %{
          # Already at max
          "attempt_number" => 2,
          "max_attempts" => 2,
          "resume_at" => DateTime.add(DateTime.utc_now(), 1000, :millisecond),
          "original_error" => "Previous failure"
        })

      result =
        NodeExecutor.retry_node(node, execution, failed_node_execution, %{
          execution_index: 3,
          run_index: 0
        })

      # Should fail permanently (no more retries)
      assert {:error, {_reason, final_failed_execution}} = result
      assert final_failed_execution.status == "failed"
    end
  end

  describe "retry_node/4 error handling" do
    test "retry_node handles action not found errors", %{execution: execution} do
      settings = NodeSettings.new(%{retry_on_failed: true, max_retries: 2})
      node = Node.new("Bad Action", "nonexistent.action")
      node = %{node | settings: settings}

      failed_node_execution = NodeExecution.new(node.key, 1, 0)
      failed_node_execution = NodeExecution.start(failed_node_execution)

      failed_node_execution =
        NodeExecution.suspend(failed_node_execution, :retry, %{
          "attempt_number" => 1,
          "max_attempts" => 2
        })

      result =
        NodeExecutor.retry_node(node, execution, failed_node_execution, %{
          execution_index: 2,
          run_index: 0
        })

      # Should fail immediately - action not found is not retryable
      assert {:error, {reason, failed_execution}} = result
      assert reason.code == "action_not_found"
      assert failed_execution.status == "failed"
    end
  end

  describe "retry_node/4 vs resume_node/5 separation" do
    test "retry_node calls action.execute(), not action.resume()", %{execution: execution} do
      # This test verifies that retry_node rebuilds input and calls execute
      # rather than using stored params and calling resume

      settings = NodeSettings.new(%{retry_on_failed: true, max_retries: 2})
      node = Node.new("Execute vs Resume", "test.success_after_retry")
      node = %{node | settings: settings}

      failed_node_execution = NodeExecution.new(node.key, 1, 0)
      failed_node_execution = NodeExecution.start(failed_node_execution)

      failed_node_execution =
        NodeExecution.suspend(failed_node_execution, :retry, %{
          "attempt_number" => 1,
          "max_attempts" => 2
        })

      execution = %{
        execution
        | execution_data: %{
            execution.execution_data
            | "context_data" => %{
                execution.execution_data["context_data"]
                | "workflow" => Map.put(execution.execution_data["context_data"]["workflow"], "retry_count", 1)
              }
          }
      }

      # Call retry_node
      retry_result =
        NodeExecutor.retry_node(node, execution, failed_node_execution, %{
          execution_index: 2,
          run_index: 0
        })

      # Should succeed because action.execute() sees retry context
      assert {:ok, completed_execution, _} = retry_result
      assert completed_execution.output_data[:message] == "Success on retry"

      # Compare with resume_node which would not have retry context
      suspended_for_resume = NodeExecution.suspend(failed_node_execution, :webhook, %{})

      resume_result =
        NodeExecutor.resume_node(node, execution, suspended_for_resume, %{}, %{
          execution_index: 3,
          run_index: 0
        })

      # Resume would fail because action.resume() is not implemented for our test action
      assert {:error, _} = resume_result
    end
  end

  describe "retry_node/4 context and state" do
    test "retry_node preserves original execution context", %{execution: execution} do
      settings = NodeSettings.new(%{retry_on_failed: true, max_retries: 2})
      node = Node.new("Context Test", "test.success_after_retry")
      node = %{node | settings: settings}

      # Create execution with specific context
      execution = %{
        execution
        | vars: %{"test_var" => "test_value"},
          execution_data: %{
            "context_data" => %{
              "workflow" => %{
                "retry_count" => 1,
                "custom_state" => "preserved"
              }
            }
          }
      }

      failed_node_execution = NodeExecution.new(node.key, 1, 0)
      failed_node_execution = NodeExecution.start(failed_node_execution)

      failed_node_execution =
        NodeExecution.suspend(failed_node_execution, :retry, %{
          "attempt_number" => 1
        })

      result =
        NodeExecutor.retry_node(node, execution, failed_node_execution, %{
          execution_index: 2,
          run_index: 0
        })

      # Should succeed and preserve context
      assert {:ok, _completed_execution, updated_execution} = result
      assert updated_execution.vars == execution.vars
      assert get_in(updated_execution.execution_data, ["context_data", "workflow", "custom_state"]) == "preserved"
    end
  end
end
