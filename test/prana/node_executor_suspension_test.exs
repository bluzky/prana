defmodule Prana.NodeExecutorSuspensionTest do
  use ExUnit.Case, async: false

  alias Prana.Action
  alias Prana.Execution
  alias Prana.IntegrationRegistry
  alias Prana.Node
  alias Prana.NodeExecutor

  setup do
    # Start registry for tests
    {:ok, registry_pid} = Prana.IntegrationRegistry.start_link()

    # Ensure modules are loaded before registration
    Code.ensure_loaded!(Prana.Integrations.Workflow)
    Code.ensure_loaded!(Prana.Integrations.Manual)

    # Register integrations for testing
    :ok = IntegrationRegistry.register_integration(Prana.Integrations.Workflow)
    :ok = IntegrationRegistry.register_integration(Prana.Integrations.Manual)

    # Create test execution with unified architecture
    execution = %Execution{
      id: "test_execution",
      workflow_id: "test_workflow",
      workflow_version: 1,
      execution_mode: "node_executor_test",
      status: :running,
      input_data: %{"api_url" => "https://api.test.com"},
      node_executions: [],
      __runtime: %{
        "nodes" => %{},
        "env" => %{},
        "active_paths" => %{},
        "executed_nodes" => []
      }
    }
    execution = Execution.rebuild_runtime(execution, %{})

    on_exit(fn ->
      if Process.alive?(registry_pid) do
        GenServer.stop(registry_pid)
      end
    end)

    {:ok, execution: execution}
  end

  describe "execute_node/3 with suspension" do
    test "handles synchronous sub-workflow suspension", %{execution: execution} do
      node = %Node{
        id: "sub_workflow_node",
        custom_id: "sub_workflow_node",
        type: :action,
        integration_name: "workflow",
        action_name: "execute_workflow",
        input_map: %{
          "workflow_id" => "user_onboarding",
          "input_data" => %{"user_id" => "$vars.user_id"},
          "execution_mode" => "sync",
          "timeout_ms" => 300_000
        }
      }

      # Add user_id to execution input_data for expression evaluation
      updated_execution = %{execution | input_data: Map.put(execution.input_data, "user_id", 123)}
      routed_input = %{"primary" => updated_execution.input_data}

      result = NodeExecutor.execute_node(node, updated_execution, routed_input)

      assert {:suspend, suspended_node_execution} = result

      # Verify suspended node execution
      assert suspended_node_execution.node_id == "sub_workflow_node"
      assert suspended_node_execution.status == :suspended
      assert suspended_node_execution.output_data == nil
      assert suspended_node_execution.output_port == nil
      assert suspended_node_execution.completed_at == nil
      assert suspended_node_execution.duration_ms == nil

      # Verify suspension data stored in NodeExecution
      assert suspended_node_execution.suspension_type == :sub_workflow_sync
      suspend_data = suspended_node_execution.suspension_data
      assert suspend_data.workflow_id == "user_onboarding"
      assert suspend_data.input_data == %{"user_id" => 123}
      assert suspend_data.execution_mode == "sync"
      assert suspend_data.timeout_ms == 300_000
      assert suspend_data.failure_strategy == "fail_parent"
      assert %DateTime{} = suspend_data.triggered_at
    end

    test "handles fire-and-forget sub-workflow execution", %{execution: execution} do
      node = %Node{
        id: "notification_node",
        custom_id: "notification_node",
        type: :action,
        integration_name: "workflow",
        action_name: "execute_workflow",
        input_map: %{
          "workflow_id" => "notification_flow",
          "input_data" => %{"message" => "Hello World"},
          "execution_mode" => "fire_and_forget"
        }
      }

      routed_input = %{"primary" => execution.input_data}
      result = NodeExecutor.execute_node(node, execution, routed_input)

      assert {:suspend, suspended_node_execution} = result

      # Verify suspended node execution
      assert suspended_node_execution.node_id == "notification_node"
      assert suspended_node_execution.status == :suspended

      # Verify suspension data stored in NodeExecution
      assert suspended_node_execution.suspension_type == :sub_workflow_fire_forget
      suspend_data = suspended_node_execution.suspension_data
      assert suspend_data.workflow_id == "notification_flow"
      assert suspend_data.input_data == %{"message" => "Hello World"}
      assert suspend_data.execution_mode == "fire_and_forget"
      assert %DateTime{} = suspend_data.triggered_at
    end

    test "handles sub-workflow validation errors", %{execution: execution} do
      node = %Node{
        id: "invalid_node",
        custom_id: "invalid_node",
        type: :action,
        integration_name: "workflow",
        action_name: "execute_workflow",
        input_map: %{
          # Invalid empty workflow_id
          "workflow_id" => "",
          "wait_for_completion" => true
        }
      }

      routed_input = %{"primary" => execution.input_data}
      result = NodeExecutor.execute_node(node, execution, routed_input)

      assert {:error, {error_data, failed_node_execution}} = result

      # Verify error details - the structure is nested under "error" with atom keys
      assert error_data["type"] == "action_error"
      assert error_data["error"].type == "sub_workflow_setup_error"
      assert error_data["error"].message == "workflow_id cannot be empty"
      assert error_data["port"] == "error"

      # Verify failed node execution
      assert failed_node_execution.node_id == "invalid_node"
      assert failed_node_execution.status == :failed
      assert failed_node_execution.error_data == error_data
      assert failed_node_execution.output_port == nil
    end

    test "processes expressions in sub-workflow input_data", %{execution: execution} do
      node = %Node{
        id: "expression_node",
        custom_id: "expression_node",
        type: :action,
        integration_name: "workflow",
        action_name: "execute_workflow",
        input_map: %{
          "workflow_id" => "expression_flow",
          "input_data" => %{
            "api_url" => "$vars.api_url",
            "static_value" => "test"
          },
          "wait_for_completion" => true
        }
      }

      routed_input = %{"primary" => execution.input_data}
      result = NodeExecutor.execute_node(node, execution, routed_input)

      assert {:suspend, suspended_node_execution} = result
      suspend_data = suspended_node_execution.suspension_data
      assert suspended_node_execution.suspension_type == :sub_workflow_sync

      # Verify expressions were evaluated
      assert suspend_data.input_data["api_url"] == "https://api.test.com"
      assert suspend_data.input_data["static_value"] == "test"
    end

    test "handles complex nested expressions", %{execution: execution} do
      # Add complex data to execution input_data
      complex_execution = %{
        execution
        | input_data:
            Map.put(execution.input_data, "user", %{
              "id" => 456,
              "profile" => %{"name" => "Jane", "role" => "admin"}
            })
      }

      node = %Node{
        id: "complex_node",
        custom_id: "complex_node",
        type: :action,
        integration_name: "workflow",
        action_name: "execute_workflow",
        input_map: %{
          "workflow_id" => "complex_flow",
          "input_data" => %{
            "user_id" => "$vars.user.id",
            "user_name" => "$vars.user.profile.name",
            "is_admin" => true
          },
          "timeout_ms" => 600_000
        }
      }

      routed_input = %{"primary" => complex_execution.input_data}
      result = NodeExecutor.execute_node(node, complex_execution, routed_input)

      assert {:suspend, suspended_node_execution} = result
      suspend_data = suspended_node_execution.suspension_data
      assert suspended_node_execution.suspension_type == :sub_workflow_sync

      # Verify complex expressions were evaluated correctly
      assert suspend_data.input_data["user_id"] == 456
      assert suspend_data.input_data["user_name"] == "Jane"
      assert suspend_data.input_data["is_admin"] == true
      assert suspend_data.timeout_ms == 600_000
    end

    test "handles action execution exceptions gracefully", %{execution: execution} do
      # Create a node that will cause an expression evaluation error (non-existent reference returns nil)
      # This actually succeeds but with nil value, demonstrating graceful handling
      node = %Node{
        id: "error_node",
        custom_id: "error_node",
        type: :action,
        integration_name: "workflow",
        action_name: "execute_workflow",
        input_map: %{
          "workflow_id" => "test_flow",
          "input_data" => %{
            "invalid_reference" => "$vars.nonexistent.deeply.nested.field"
          }
        }
      }

      routed_input = %{"primary" => execution.input_data}
      result = NodeExecutor.execute_node(node, execution, routed_input)

      # Expression engine returns nil for non-existent references, so this will succeed with suspension
      assert {:suspend, suspended_node_execution} = result
      suspend_data = suspended_node_execution.suspension_data
      assert suspended_node_execution.suspension_type == :sub_workflow_sync

      # Verify that the invalid reference was handled gracefully (set to nil)
      assert suspend_data.input_data["invalid_reference"] == nil
      assert suspended_node_execution.status == :suspended
      assert suspended_node_execution.node_id == "error_node"
    end

    test "preserves node execution timing for suspended nodes", %{execution: execution} do
      node = %Node{
        id: "timing_node",
        custom_id: "timing_node",
        type: :action,
        integration_name: "workflow",
        action_name: "execute_workflow",
        input_map: %{
          "workflow_id" => "timing_flow",
          "wait_for_completion" => true
        }
      }

      # Record time before execution
      before_time = DateTime.utc_now()

      routed_input = %{"primary" => execution.input_data}
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
        output_ports: ["success", "error"],
        default_success_port: "success",
        default_error_port: "error"
      }

      suspend_data = %{workflow_id: "test", data: %{}}
      result = {:suspend, :sub_workflow_sync, suspend_data}

      processed = NodeExecutor.process_action_result(result, action)

      assert {:suspend, :sub_workflow_sync, ^suspend_data} = processed
    end

    test "handles different suspension types" do
      action = %Action{
        name: "test_action",
        output_ports: ["success", "error"]
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
        suspend_data = %{type: suspension_type, config: %{}}
        result = {:suspend, suspension_type, suspend_data}

        processed = NodeExecutor.process_action_result(result, action)

        assert {:suspend, ^suspension_type, ^suspend_data} = processed
      end
    end

    test "validates suspension tuple format" do
      action = %Action{
        name: "test_action",
        output_ports: ["success", "error"]
      }

      # Invalid suspension type (not an atom)
      invalid_result = {:suspend, "invalid_type", %{}}

      processed = NodeExecutor.process_action_result(invalid_result, action)

      assert {:error, error_data} = processed
      assert error_data["type"] == "invalid_action_return_format"
      assert error_data["message"] =~ "Actions must return"
    end
  end
end
