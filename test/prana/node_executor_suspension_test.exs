defmodule Prana.NodeExecutorSuspensionTest do
  use ExUnit.Case, async: false

  alias Prana.Action
  alias Prana.IntegrationRegistry
  alias Prana.Integrations.Manual
  alias Prana.Integrations.Workflow
  alias Prana.Node
  alias Prana.NodeExecutor
  alias Prana.WorkflowExecution

  setup do
    # Start registry for tests or get existing process
    registry_pid =
      case IntegrationRegistry.start_link() do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    # Ensure modules are loaded before registration
    Code.ensure_loaded!(Workflow)
    Code.ensure_loaded!(Manual)

    # Register integrations for testing
    :ok = IntegrationRegistry.register_integration(Workflow)
    :ok = IntegrationRegistry.register_integration(Manual)

    # Create test execution with unified architecture
    execution = %WorkflowExecution{
      id: "test_execution",
      workflow_id: "test_workflow",
      workflow_version: 1,
      execution_graph: %{
        trigger_node_key: "start_node"
      },
      execution_mode: "node_executor_test",
      status: "running",
      vars: %{"api_url" => "https://api.test.com"},
      node_executions: %{},
      __runtime: %{
        "nodes" => %{},
        "env" => %{},
        "active_paths" => %{},
        "executed_nodes" => []
      }
    }

    execution = WorkflowExecution.rebuild_runtime(execution, %{})

    # Clean up registry on exit only if we started it
    on_exit(fn ->
      # Only stop if we started it and it's still the same process
      if Process.alive?(registry_pid) do
        case Process.info(registry_pid, :registered_name) do
          {:registered_name, IntegrationRegistry} ->
            # This is the named registry - don't stop it as other tests might need it
            :ok

          _ ->
            # This is an unnamed process we started - safe to stop
            GenServer.stop(registry_pid)
        end
      end
    end)

    {:ok, execution: execution}
  end

  describe "execute_node/3 with suspension" do
    test "handles synchronous sub-workflow suspension", %{execution: execution} do
      node = %Node{
        key: "sub_workflow_node",
        type: "workflow.execute_workflow",
        params: %{
          "workflow_id" => "user_onboarding",
          "execution_mode" => "sync",
          "timeout_ms" => 300_000
        }
      }

      # Add user_id to execution vars for expression evaluation
      updated_execution = %{execution | vars: Map.put(execution.vars, "user_id", 123)}
      routed_input = %{"primary" => updated_execution.vars}

      result = NodeExecutor.execute_node(node, updated_execution, routed_input)

      assert {:suspend, suspended_node_execution} = result

      # Verify suspended node execution
      assert suspended_node_execution.node_key == "sub_workflow_node"
      assert suspended_node_execution.status == "suspended"
      assert suspended_node_execution.output_data == nil
      assert suspended_node_execution.output_port == nil
      assert suspended_node_execution.completed_at == nil
      assert suspended_node_execution.duration_ms == nil

      # Verify suspension data stored in NodeExecution
      assert suspended_node_execution.suspension_type == :sub_workflow_sync
      suspension_data = suspended_node_execution.suspension_data
      assert suspension_data.workflow_id == "user_onboarding"
      assert suspension_data.execution_mode == "sync"
      assert suspension_data.timeout_ms == 300_000
      assert suspension_data.failure_strategy == "fail_parent"
      assert %DateTime{} = suspension_data.triggered_at
    end

    test "handles fire-and-forget sub-workflow execution", %{execution: execution} do
      node = %Node{
        key: "notification_node",
        type: "workflow.execute_workflow",
        params: %{
          "workflow_id" => "notification_flow",
          "execution_mode" => "fire_and_forget"
        }
      }

      routed_input = %{"primary" => execution.vars}
      result = NodeExecutor.execute_node(node, execution, routed_input)

      assert {:suspend, suspended_node_execution} = result

      # Verify suspended node execution
      assert suspended_node_execution.node_key == "notification_node"
      assert suspended_node_execution.status == "suspended"

      # Verify suspension data stored in NodeExecution
      assert suspended_node_execution.suspension_type == :sub_workflow_fire_forget
      suspension_data = suspended_node_execution.suspension_data
      assert suspension_data.workflow_id == "notification_flow"
      assert suspension_data.execution_mode == "fire_and_forget"
      assert %DateTime{} = suspension_data.triggered_at
    end

    test "handles sub-workflow validation errors", %{execution: execution} do
      node = %Node{
        key: "invalid_node",
        type: "workflow.execute_workflow",
        params: %{
          # Invalid empty workflow_id
          "workflow_id" => "",
          "wait_for_completion" => true
        }
      }

      routed_input = %{"primary" => execution.vars}
      result = NodeExecutor.execute_node(node, execution, routed_input)

      assert {:error, {error_data, failed_node_execution}} = result

      # Verify error details - the structure is nested under "error" with atom keys
      assert error_data.code == "action_error"
      assert error_data.details["error"].code == "action_error"

      assert error_data.details["error"].message ==
               "errors: %{workflow_id: [\"length must be greater than or equal to 1\"]}"

      assert error_data.details["port"] == "error"

      # Verify failed node execution
      assert failed_node_execution.node_key == "invalid_node"
      assert failed_node_execution.status == "failed"
      assert failed_node_execution.error_data == error_data
      assert failed_node_execution.output_port == nil
    end

    test "preserves node execution timing for suspended nodes", %{execution: execution} do
      node = %Node{
        key: "timing_node",
        type: "workflow.execute_workflow",
        params: %{
          "workflow_id" => "timing_flow",
          "wait_for_completion" => true
        }
      }

      # Record time before execution
      before_time = DateTime.utc_now()

      routed_input = %{"primary" => execution.vars}
      result = NodeExecutor.execute_node(node, execution, routed_input)

      assert {:suspend, suspended_node_execution} = result
      assert suspended_node_execution.suspension_type == :sub_workflow_sync

      # Verify timing information
      assert %DateTime{} = suspended_node_execution.started_at
      assert DateTime.compare(suspended_node_execution.started_at, before_time) in [:gt, :eq]

      # Suspended nodes should not have completion timing yet
      assert suspended_node_execution.completed_at == nil
      assert suspended_node_execution.duration_ms == nil

      # Verify suspension data is present
      assert suspended_node_execution.suspension_type != nil
      assert suspended_node_execution.suspension_data != nil
    end
  end

  describe "process_action_result/2 suspension handling" do
    test "processes suspension tuple correctly" do
      action = %Action{
        name: "test_action",
        output_ports: ["main", "error"]
      }

      suspension_data = %{workflow_id: "test", data: %{}}
      result = {:suspend, :sub_workflow_sync, suspension_data}

      processed = NodeExecutor.process_action_result(result, action)

      assert {:suspend, :sub_workflow_sync, ^suspension_data} = processed
    end

    test "handles different suspension types" do
      action = %Action{
        name: "test_action",
        output_ports: ["main", "error"]
      }

      # Test different suspension types
      suspension_types = [
        :sub_workflow_sync,
        :sub_workflow_async,
        :sub_workflow_fire_forget,
        :external_event,
        :delay,
        :poll_until
      ]

      for suspension_type <- suspension_types do
        suspension_data = %{type: suspension_type, config: %{}}
        result = {:suspend, suspension_type, suspension_data}

        processed = NodeExecutor.process_action_result(result, action)

        assert {:suspend, ^suspension_type, ^suspension_data} = processed
      end
    end

    test "validates suspension tuple format" do
      action = %Action{
        name: "test_action",
        output_ports: ["main", "error"]
      }

      # Invalid suspension type (not an atom)
      invalid_result = {:suspend, "invalid_type", %{}}

      processed = NodeExecutor.process_action_result(invalid_result, action)

      assert {:error, error_data} = processed
      assert error_data.code == "invalid_action_return_format"
      assert error_data.message =~ "Actions must return"
    end
  end
end
