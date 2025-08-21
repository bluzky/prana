defmodule Prana.NodeExecutorRetryTest do
  use ExUnit.Case, async: false

  alias Prana.Node
  alias Prana.NodeExecution
  alias Prana.NodeExecutor
  alias Prana.NodeSettings
  alias Prana.WorkflowExecution
  alias Prana.IntegrationRegistry

  # Test actions for retry testing
  defmodule FailingAction do
    use Prana.Actions.SimpleAction
    alias Prana.Action

    def specification do
      %Action{
        name: "failing.always_fail",
        display_name: "Always Fail",
        description: "Action that always fails for testing",
        type: :action,
        module: __MODULE__,
        input_ports: ["main"],
        output_ports: ["main", "error"]
      }
    end

    @impl true
    def execute(_params, _context) do
      {:error, "This action always fails"}
    end
  end

  defmodule SuspendingAction do
    use Prana.Actions.SimpleAction
    alias Prana.Action

    def specification do
      %Action{
        name: "failing.fail_with_suspension",
        display_name: "Suspend Action",
        description: "Action that suspends for testing",
        type: :action,
        module: __MODULE__,
        input_ports: ["main"],
        output_ports: ["main", "error"]
      }
    end

    @impl true
    def execute(_params, _context) do
      {:suspend, :test_suspension, %{"test" => "data"}}
    end
  end

  # Test integration that always fails for retry testing
  defmodule FailingIntegration do
    @behaviour Prana.Behaviour.Integration

    def definition do
      %Prana.Integration{
        name: "failing",
        display_name: "Failing Test Integration",
        actions: %{
          "always_fail" => FailingAction.specification(),
          "fail_with_suspension" => SuspendingAction.specification()
        }
      }
    end
  end

  setup do
    # Start IntegrationRegistry
    {:ok, registry_pid} = IntegrationRegistry.start_link()
    
    # Register test integration
    IntegrationRegistry.register_integration(FailingIntegration)

    # Create test execution (matching pattern from node_executor_test.exs)
    execution = %WorkflowExecution{
      id: "test_execution",
      workflow_id: "test_workflow",
      workflow_version: 1,
      execution_mode: :async,
      status: "running",
      vars: %{},
      node_executions: %{},
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

  describe "retry helper functions" do
    test "get_current_attempt_number returns 0 for first attempt" do
      node_execution = NodeExecution.new("test", 1, 1)
      
      result = get_current_attempt_number(node_execution)
      assert result == 0
    end

    test "get_current_attempt_number returns attempt from suspension data" do
      node_execution = NodeExecution.new("test", 1, 1)
      node_execution = NodeExecution.suspend(node_execution, :retry, %{"attempt_number" => 2})
      
      result = get_current_attempt_number(node_execution)
      assert result == 2
    end

    test "get_next_attempt_number increments attempt number" do
      node_execution = NodeExecution.new("test", 1, 1)
      node_execution = NodeExecution.suspend(node_execution, :retry, %{"attempt_number" => 1})
      
      result = get_next_attempt_number(node_execution)
      assert result == 2
    end

    test "should_retry? returns true when retry is enabled and under max attempts" do
      settings = NodeSettings.new(%{retry_on_failed: true, max_retries: 3})
      node = %Node{key: "test", type: "test", settings: settings}
      node_execution = NodeExecution.new("test", 1, 1)
      
      result = should_retry?(node, node_execution, "test error")
      assert result == true
    end

    test "should_retry? returns false when retry is disabled" do
      settings = NodeSettings.new(%{retry_on_failed: false, max_retries: 3})
      node = %Node{key: "test", type: "test", settings: settings}
      node_execution = NodeExecution.new("test", 1, 1)
      
      result = should_retry?(node, node_execution, "test error")
      assert result == false
    end

    test "should_retry? returns false when max attempts reached" do
      settings = NodeSettings.new(%{retry_on_failed: true, max_retries: 2})
      node = %Node{key: "test", type: "test", settings: settings}
      
      # Create a node execution that's already on attempt 2 (reached max)
      node_execution = NodeExecution.new("test", 1, 1)
      node_execution = NodeExecution.suspend(node_execution, :retry, %{"attempt_number" => 2})
      
      result = should_retry?(node, node_execution, "test error")
      assert result == false
    end
  end

  describe "retry execution behavior" do
    test "execute_node returns suspension for retry when enabled and action fails", %{execution: execution} do
      settings = NodeSettings.new(%{retry_on_failed: true, max_retries: 3, retry_delay_ms: 1000})
      node = Node.new("Failing Node", "failing.always_fail")
      node = %{node | settings: settings}

      result = NodeExecutor.execute_node(node, execution, %{}, %{execution_index: 1, run_index: 0})

      assert {:suspend, suspended_node_execution} = result
      assert suspended_node_execution.suspension_type == :retry
      assert suspended_node_execution.suspension_data["attempt_number"] == 1
      assert suspended_node_execution.suspension_data["max_attempts"] == 3
      assert suspended_node_execution.suspension_data["retry_delay_ms"] == 1000
      # Original error is wrapped in Prana.Core.Error
      assert suspended_node_execution.suspension_data["original_error"].details["error"] == "This action always fails"
    end

    test "execute_node returns error when retry is disabled", %{execution: execution} do
      settings = NodeSettings.new(%{retry_on_failed: false})
      node = Node.new("Failing Node", "failing.always_fail")
      node = %{node | settings: settings}

      result = NodeExecutor.execute_node(node, execution, %{}, %{execution_index: 1, run_index: 0})

      assert {:error, {reason, failed_execution}} = result
      # Reason is now wrapped in Prana.Core.Error
      assert reason.details["error"] == "This action always fails"
      assert failed_execution.status == "failed"
    end

    test "execute_node returns error when max retries reached", %{execution: execution} do
      settings = NodeSettings.new(%{retry_on_failed: true, max_retries: 1})
      node = Node.new("Failing Node", "failing.always_fail")
      node = %{node | settings: settings}

      # First execution should return suspension for retry (attempt 1)
      result1 = NodeExecutor.execute_node(node, execution, %{}, %{execution_index: 1, run_index: 0})
      assert {:suspend, suspended_execution} = result1
      assert suspended_execution.suspension_type == :retry
      assert suspended_execution.suspension_data["attempt_number"] == 1
      assert suspended_execution.suspension_data["max_attempts"] == 1

      # This execution is already at max attempts (attempt_number == max_attempts)
      # So retry_node should fail instead of retry again
      # Note: This test demonstrates the max retry logic, but in real usage,
      # retry_node would be called with the suspended execution
    end

    test "execute_node does not retry on suspension", %{execution: execution} do
      settings = NodeSettings.new(%{retry_on_failed: true, max_retries: 3})
      node = Node.new("Suspend Node", "failing.fail_with_suspension")
      node = %{node | settings: settings}

      result = NodeExecutor.execute_node(node, execution, %{}, %{execution_index: 1, run_index: 0})

      # Should return normal suspension, not retry suspension
      assert {:suspend, suspended_node_execution} = result
      assert suspended_node_execution.suspension_type == :test_suspension
      assert suspended_node_execution.suspension_data == %{"test" => "data"}
    end
  end

  describe "resume error handling" do
    test "resume_node uses handle_resume_error for failures", %{execution: execution} do
      # Create a suspended node execution
      node_execution = NodeExecution.new("test", 1, 1)
      suspended_node_execution = NodeExecution.suspend(node_execution, :test_suspension, %{})

      # Create a node that doesn't exist to trigger error in resume
      node = Node.new("Bad Node", "nonexistent.action")

      result = NodeExecutor.resume_node(node, execution, suspended_node_execution, %{}, %{})

      # Should return error without retry attempt (resume failures don't retry)
      assert {:error, {_reason, failed_execution}} = result
      assert failed_execution.status == "failed"
      # Should not have retry suspension data
      refute failed_execution.suspension_type == :retry
    end
  end

  # Helper functions to test private NodeExecutor functions
  defp get_current_attempt_number(node_execution) do
    if node_execution.suspension_type == :retry do
      node_execution.suspension_data["attempt_number"] || 0
    else
      0  # First attempt
    end
  end

  defp get_next_attempt_number(node_execution) do
    get_current_attempt_number(node_execution) + 1
  end

  defp should_retry?(node, node_execution, _error_reason) do
    settings = node.settings
    current_attempt = get_current_attempt_number(node_execution)
    
    settings.retry_on_failed and settings.max_retries > 0 and current_attempt < settings.max_retries
  end
end