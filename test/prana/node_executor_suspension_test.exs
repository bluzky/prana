defmodule Prana.NodeExecutorSuspensionTest do
  use ExUnit.Case, async: true

  alias Prana.Action
  alias Prana.ExecutionContext
  alias Prana.IntegrationRegistry
  alias Prana.Node
  alias Prana.NodeExecution
  alias Prana.NodeExecutor
  alias Prana.Workflow

  setup do
    # Start registry for tests
    start_supervised!(IntegrationRegistry)
    
    # Ensure modules are loaded before registration
    Code.ensure_loaded!(Prana.Integrations.Workflow)
    Code.ensure_loaded!(Prana.Integrations.Manual)
    
    # Register integrations for testing
    :ok = IntegrationRegistry.register_integration(Prana.Integrations.Workflow)
    :ok = IntegrationRegistry.register_integration(Prana.Integrations.Manual)
    
    # Create test workflow and execution context
    workflow = %Workflow{
      id: "test_workflow",
      name: "Test Workflow", 
      nodes: [],
      connections: []
    }

    execution = %Prana.Execution{
      id: "test_execution",
      workflow_id: "test_workflow",
      status: :running
    }

    context = ExecutionContext.new(workflow, execution, %{
      nodes: %{},
      variables: %{"api_url" => "https://api.test.com"}
    })

    {:ok, context: context}
  end

  describe "execute_node/3 with suspension" do
    test "handles synchronous sub-workflow suspension", %{context: context} do
      node = %Node{
        id: "sub_workflow_node",
        custom_id: "sub_workflow_node",
        type: :action,
        integration_name: "workflow",
        action_name: "execute_workflow",
        input_map: %{
          "workflow_id" => "user_onboarding",
          "input_data" => %{"user_id" => "$variables.user_id"},
          "wait_for_completion" => true,
          "timeout_ms" => 300_000
        }
      }

      # Add user_id to context variables for expression evaluation
      updated_context = %{context | variables: Map.put(context.variables, "user_id", 123)}

      result = NodeExecutor.execute_node(node, updated_context)

      assert {:suspend, :sub_workflow, suspend_data, suspended_node_execution} = result
      
      # Verify suspension data
      assert suspend_data.workflow_id == "user_onboarding"
      assert suspend_data.input_data == %{"user_id" => 123}
      assert suspend_data.wait_for_completion == true
      assert suspend_data.timeout_ms == 300_000
      assert suspend_data.failure_strategy == "fail_parent"
      assert %DateTime{} = suspend_data.triggered_at

      # Verify suspended node execution
      assert suspended_node_execution.node_id == "sub_workflow_node"
      assert suspended_node_execution.status == :suspended
      assert suspended_node_execution.output_data == nil
      assert suspended_node_execution.output_port == nil
      assert suspended_node_execution.completed_at == nil
      assert suspended_node_execution.duration_ms == nil
      
      # Verify suspension metadata
      suspension_metadata = suspended_node_execution.metadata[:suspension_data]
      assert suspension_metadata.type == :sub_workflow
      assert suspension_metadata.data == suspend_data
      assert %DateTime{} = suspension_metadata.suspended_at
    end

    test "handles fire-and-forget sub-workflow execution", %{context: context} do
      node = %Node{
        id: "notification_node",
        custom_id: "notification_node", 
        type: :action,
        integration_name: "workflow",
        action_name: "execute_workflow",
        input_map: %{
          "workflow_id" => "notification_flow",
          "input_data" => %{"message" => "Hello World"},
          "wait_for_completion" => false
        }
      }

      result = NodeExecutor.execute_node(node, context)

      assert {:ok, completed_node_execution, updated_context} = result
      
      # Verify completed execution
      assert completed_node_execution.node_id == "notification_node"
      assert completed_node_execution.status == :completed
      assert completed_node_execution.output_port == "success"
      assert completed_node_execution.output_data.sub_workflow_triggered == true
      assert completed_node_execution.output_data.workflow_id == "notification_flow"
      assert %DateTime{} = completed_node_execution.completed_at
      
      # Verify context updated with node result
      assert updated_context.nodes["notification_node"] == completed_node_execution.output_data
    end

    test "handles sub-workflow validation errors", %{context: context} do
      node = %Node{
        id: "invalid_node",
        custom_id: "invalid_node",
        type: :action, 
        integration_name: "workflow",
        action_name: "execute_workflow",
        input_map: %{
          "workflow_id" => "",  # Invalid empty workflow_id
          "wait_for_completion" => true
        }
      }

      result = NodeExecutor.execute_node(node, context)

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

    test "processes expressions in sub-workflow input_data", %{context: context} do
      node = %Node{
        id: "expression_node",
        custom_id: "expression_node",
        type: :action,
        integration_name: "workflow", 
        action_name: "execute_workflow",
        input_map: %{
          "workflow_id" => "expression_flow",
          "input_data" => %{
            "api_url" => "$variables.api_url",
            "static_value" => "test"
          },
          "wait_for_completion" => true
        }
      }

      result = NodeExecutor.execute_node(node, context)

      assert {:suspend, :sub_workflow, suspend_data, _} = result
      
      # Verify expressions were evaluated
      assert suspend_data.input_data["api_url"] == "https://api.test.com"
      assert suspend_data.input_data["static_value"] == "test"
    end

    test "handles complex nested expressions", %{context: context} do
      # Add complex data to context
      complex_context = %{context | 
        variables: Map.put(context.variables, "user", %{
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
            "user_id" => "$variables.user.id",
            "user_name" => "$variables.user.profile.name",
            "is_admin" => true
          },
          "timeout_ms" => 600_000
        }
      }

      result = NodeExecutor.execute_node(node, complex_context)

      assert {:suspend, :sub_workflow, suspend_data, _} = result
      
      # Verify complex expressions were evaluated correctly
      assert suspend_data.input_data["user_id"] == 456
      assert suspend_data.input_data["user_name"] == "Jane"
      assert suspend_data.input_data["is_admin"] == true
      assert suspend_data.timeout_ms == 600_000
    end

    test "handles action execution exceptions gracefully", %{context: context} do
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
            "invalid_reference" => "$variables.nonexistent.deeply.nested.field"
          }
        }
      }

      result = NodeExecutor.execute_node(node, context)

      # Expression engine returns nil for non-existent references, so this will succeed with suspension
      assert {:suspend, :sub_workflow, suspend_data, suspended_node_execution} = result
      
      # Verify that the invalid reference was handled gracefully (set to nil)
      assert suspend_data.input_data["invalid_reference"] == nil
      assert suspended_node_execution.status == :suspended
      assert suspended_node_execution.node_id == "error_node"
    end

    test "preserves node execution timing for suspended nodes", %{context: context} do
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
      
      result = NodeExecutor.execute_node(node, context)

      assert {:suspend, :sub_workflow, _, suspended_node_execution} = result
      
      # Verify timing information
      assert %DateTime{} = suspended_node_execution.started_at
      assert DateTime.compare(suspended_node_execution.started_at, before_time) in [:gt, :eq]
      
      # Suspended nodes should not have completion timing yet
      assert suspended_node_execution.completed_at == nil
      assert suspended_node_execution.duration_ms == nil
      
      # But should have suspension timing in metadata
      suspension_metadata = suspended_node_execution.metadata[:suspension_data]
      assert %DateTime{} = suspension_metadata.suspended_at
      assert DateTime.compare(suspension_metadata.suspended_at, suspended_node_execution.started_at) in [:gt, :eq]
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
      result = {:suspend, :sub_workflow, suspend_data}

      processed = NodeExecutor.process_action_result(result, action)

      assert {:suspend, :sub_workflow, ^suspend_data} = processed
    end

    test "handles different suspension types" do
      action = %Action{
        name: "test_action",
        output_ports: ["success", "error"]
      }

      # Test different suspension types
      suspension_types = [:sub_workflow, :external_event, :delay, :poll_until]
      
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