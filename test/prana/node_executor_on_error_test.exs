defmodule Prana.NodeExecutorOnErrorTest do
  use ExUnit.Case, async: false

  alias Prana.IntegrationRegistry
  alias Prana.Node
  alias Prana.NodeExecutor
  alias Prana.NodeSettings
  alias Prana.TestSupport.TestIntegration
  alias Prana.WorkflowExecution

  setup do
    # Start IntegrationRegistry
    {:ok, registry_pid} = IntegrationRegistry.start_link()

    # Register test integration
    :ok = IntegrationRegistry.register_integration(TestIntegration)

    # Create basic execution
    execution = %WorkflowExecution{
      id: "test_execution",
      workflow_id: "test_workflow",
      workflow_version: "1.0.0",
      status: "running",
      node_executions: %{},
      execution_data: %{"context_data" => %{}},
      preparation_data: %{},
      vars: %{},
      __runtime: %{
        "nodes" => %{},
        "env" => %{},
        "ready_nodes" => MapSet.new(),
        "active_paths" => MapSet.new(),
        "executed_nodes" => MapSet.new()
      }
    }

    on_exit(fn ->
      if Process.alive?(registry_pid) do
        GenServer.stop(registry_pid)
      end
    end)

    {:ok, %{execution: execution}}
  end

  describe "on_error: stop_workflow (default behavior)" do
    test "fails workflow when node encounters error", %{execution: execution} do
      node = %Node{
        key: "test_node",
        type: "test.failing_action",
        settings: %NodeSettings{on_error: "stop_workflow"}
      }

      routed_input = %{}
      result = NodeExecutor.execute_node(node, execution, routed_input, %{execution_index: 1, run_index: 0})

      assert {:error, {_reason, failed_execution}} = result
      assert failed_execution.status == "failed"
      # Error is wrapped as action.execution_error with nested original error
      assert failed_execution.error_data.code == "action.execution_error"
      assert failed_execution.error_data.details[:code] == "action_error"
      assert failed_execution.output_port == nil
    end
  end

  describe "on_error: continue" do
    test "completes node successfully with error data through default port", %{execution: execution} do
      node = %Node{
        key: "test_node",
        type: "test.failing_action",
        settings: %NodeSettings{on_error: "continue"}
      }

      routed_input = %{}
      result = NodeExecutor.execute_node(node, execution, routed_input, %{execution_index: 1, run_index: 0})

      assert {:ok, completed_execution, _updated_execution} = result
      assert completed_execution.status == "completed"
      # default success port
      assert completed_execution.output_port == "main"
      assert completed_execution.output_data.code == "action_error"
      assert completed_execution.output_data.message == "Action returned error"
      # Error details are nested inside the error struct from the original action
      assert completed_execution.output_data.details[:error][:code] == "action_error"
      assert completed_execution.output_data.details[:error][:details][:error] == "This action always fails"
      # The port in details should be the original error port from the action
      # For "continue" mode, we route through default port but preserve original error info
      assert completed_execution.output_data.details[:on_error_behavior] == "default_port"
    end
  end

  describe "on_error: continue_error_output" do
    test "completes node successfully with error data through virtual error port", %{execution: execution} do
      node = %Node{
        key: "test_node",
        type: "test.failing_action",
        settings: %NodeSettings{on_error: "continue_error_output"}
      }

      routed_input = %{}
      result = NodeExecutor.execute_node(node, execution, routed_input, %{execution_index: 1, run_index: 0})

      assert {:ok, completed_execution, _updated_execution} = result
      assert completed_execution.status == "completed"
      # virtual error port
      assert completed_execution.output_port == "error"
      assert completed_execution.output_data.code == "action_error"
      assert completed_execution.output_data.message == "Action returned error"
      # Error details are nested inside the error struct from the original action
      assert completed_execution.output_data.details[:error][:code] == "action_error"
      assert completed_execution.output_data.details[:error][:details][:error] == "This action always fails"
      assert completed_execution.output_data.details[:port] == "error"
      assert completed_execution.output_data.details[:on_error_behavior] == "error_port"
    end

    test "virtual error port works regardless of action definition", %{execution: execution} do
      # Even with action that doesn't have "error" port in output_ports
      node = %Node{
        key: "test_node",
        # This action only has ["main"] port
        type: "test.failing_action",
        settings: %NodeSettings{on_error: "continue_error_output"}
      }

      routed_input = %{}
      result = NodeExecutor.execute_node(node, execution, routed_input, %{execution_index: 1, run_index: 0})

      assert {:ok, completed_execution, _updated_execution} = result
      assert completed_execution.status == "completed"
      # virtual port works
      assert completed_execution.output_port == "error"
    end
  end

  describe "integration with retry logic" do
    test "retry happens before on_error processing", %{execution: execution} do
      node = %Node{
        key: "test_node",
        type: "test.failing_action",
        settings: %NodeSettings{
          on_error: "continue",
          retry_on_failed: true,
          max_retries: 3,
          retry_delay_ms: 5000
        }
      }

      routed_input = %{}
      result = NodeExecutor.execute_node(node, execution, routed_input, %{execution_index: 1, run_index: 0})

      # Should suspend for retry first (not continue yet)
      assert {:suspend, suspended_execution} = result
      assert suspended_execution.suspension_type == :retry
      assert suspended_execution.suspension_data["attempt_number"] == 1
      assert suspended_execution.suspension_data["max_attempts"] == 3
      # Original error should be wrapped and stored
      original_error = suspended_execution.suspension_data["original_error"]
      assert %Prana.Core.Error{code: "action.execution_error"} = original_error
      assert original_error.details[:code] == "action_error"
    end
  end

  describe "error data preservation" do
    test "preserves original error information in all modes", %{execution: execution} do
      test_modes = ["stop_workflow", "continue", "continue_error_output"]

      for mode <- test_modes do
        node = %Node{
          key: "test_node_#{mode}",
          type: "test.failing_action",
          settings: %NodeSettings{on_error: mode}
        }

        routed_input = %{}
        result = NodeExecutor.execute_node(node, execution, routed_input, %{execution_index: 1, run_index: 0})

        case mode do
          "stop_workflow" ->
            assert {:error, {_reason, failed_execution}} = result
            # Error is wrapped as action.execution_error with nested original error
            assert failed_execution.error_data.code == "action.execution_error"
            assert failed_execution.error_data.details[:code] == "action_error"
            assert failed_execution.error_data.details[:details][:error] == "This action always fails"

          "continue" ->
            assert {:ok, completed_execution, _updated_execution} = result
            assert completed_execution.output_data.code == "action_error"
            assert completed_execution.output_data.message == "Action returned error"
            assert completed_execution.output_data.details[:error][:code] == "action_error"
            assert completed_execution.output_data.details[:error][:details][:error] == "This action always fails"
            assert completed_execution.output_data.details[:on_error_behavior] == "default_port"

          "continue_error_output" ->
            assert {:ok, completed_execution, _updated_execution} = result
            assert completed_execution.output_data.code == "action_error"
            assert completed_execution.output_data.message == "Action returned error"
            assert completed_execution.output_data.details[:error][:code] == "action_error"
            assert completed_execution.output_data.details[:error][:details][:error] == "This action always fails"
            assert completed_execution.output_data.details[:on_error_behavior] == "error_port"
        end
      end
    end
  end
end
