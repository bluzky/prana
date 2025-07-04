defmodule Prana.NodeExecutorTest do
  use ExUnit.Case, async: false

  alias Prana.Action
  alias Prana.Execution
  alias Prana.Integration
  alias Prana.IntegrationRegistry
  alias Prana.Node
  alias Prana.NodeExecutor

  # Test Action behavior modules
  defmodule TestSuccessAction do
    @behaviour Prana.Behaviour.Action
    
    @impl true
    def prepare(_node) do
      {:ok, %{}}
    end
    
    @impl true
    def execute(input_data) do
      {:ok, %{message: "success", input: input_data}}
    end
    
    @impl true
    def resume(_suspend_data, _resume_input) do
      {:error, "Test actions do not support suspension/resume"}
    end
  end
  
  defmodule TestErrorAction do
    @behaviour Prana.Behaviour.Action
    
    @impl true
    def prepare(_node) do
      {:ok, %{}}
    end
    
    @impl true
    def execute(_input_data) do
      {:error, "something went wrong"}
    end
    
    @impl true
    def resume(_suspend_data, _resume_input) do
      {:error, "Test actions do not support suspension/resume"}
    end
  end
  
  defmodule TestTransformAction do
    @behaviour Prana.Behaviour.Action
    
    @impl true
    def prepare(_node) do
      {:ok, %{}}
    end
    
    @impl true
    def execute(input_data) do
      # Use safe approach for now
      name = case Map.get(input_data, "name") do
        nil -> ""
        name when is_binary(name) -> name
        _ -> ""
      end
      
      transformed = %{
        original: input_data,
        uppercase_name: String.upcase(name),
        timestamp: System.system_time(:second)
      }
      
      {:ok, transformed}
    end
    
    @impl true
    def resume(_suspend_data, _resume_input) do
      {:error, "Test actions do not support suspension/resume"}
    end
  end
  
  defmodule TestExplicitPortAction do
    @behaviour Prana.Behaviour.Action
    
    @impl true
    def prepare(_node) do
      {:ok, %{}}
    end
    
    @impl true
    def execute(input_data) do
      should_succeed = if is_map(input_data), do: Map.get(input_data, "should_succeed", false), else: false
      
      if should_succeed == true do
        {:ok, %{result: "explicit success"}, "custom_success"}
      else
        {:error, "explicit failure", "custom_error"}
      end
    rescue
      _ ->
        {:error, "action failed", "custom_error"}
    end
    
    @impl true
    def resume(_suspend_data, _resume_input) do
      {:error, "Test actions do not support suspension/resume"}
    end
  end
  
  defmodule TestInvalidReturnAction do
    @behaviour Prana.Behaviour.Action
    
    @impl true
    def prepare(_node) do
      {:ok, %{}}
    end
    
    @impl true
    def execute(_input_data) do
      # Return invalid format (direct value instead of tuple)
      "direct_string_value"
    end
    
    @impl true
    def resume(_suspend_data, _resume_input) do
      {:error, "Test actions do not support suspension/resume"}
    end
  end
  
  defmodule TestExceptionAction do
    @behaviour Prana.Behaviour.Action
    
    @impl true
    def prepare(_node) do
      {:ok, %{}}
    end
    
    @impl true
    def execute(_input_data) do
      raise "Test exception"
    end
    
    @impl true
    def resume(_suspend_data, _resume_input) do
      {:error, "Test actions do not support suspension/resume"}
    end
  end
  
  defmodule TestInvalidPortAction do
    @behaviour Prana.Behaviour.Action
    
    @impl true
    def prepare(_node) do
      {:ok, %{}}
    end
    
    @impl true
    def execute(_input_data) do
      {:ok, %{data: "test"}, "nonexistent_port"}
    end
    
    @impl true
    def resume(_suspend_data, _resume_input) do
      {:error, "Test actions do not support suspension/resume"}
    end
  end

  # Test integration module
  defmodule TestIntegration do
    @moduledoc false
    @behaviour Prana.Behaviour.Integration

    def definition do
      %Integration{
        name: "test",
        display_name: "Test Integration",
        description: "Integration for testing",
        version: "1.0.0",
        category: "test",
        actions: %{
          "success_action" => %Action{
            name: "success_action",
            display_name: "Success Action",
            description: "Always succeeds",
            module: TestSuccessAction,
            input_ports: ["input"],
            output_ports: ["success", "error"],
            default_success_port: "success",
            default_error_port: "error"
          },
          "error_action" => %Action{
            name: "error_action",
            display_name: "Error Action",
            description: "Always fails",
            module: TestErrorAction,
            input_ports: ["input"],
            output_ports: ["success", "error"],
            default_success_port: "success",
            default_error_port: "error"
          },
          "transform_action" => %Action{
            name: "transform_action",
            display_name: "Transform Action",
            description: "Transforms input data",
            module: TestTransformAction,
            input_ports: ["input"],
            output_ports: ["success", "error"],
            default_success_port: "success",
            default_error_port: "error"
          },
          "explicit_port_action" => %Action{
            name: "explicit_port_action",
            display_name: "Explicit Port Action",
            description: "Returns explicit port",
            module: TestExplicitPortAction,
            input_ports: ["input"],
            output_ports: ["custom_success", "custom_error"],
            default_success_port: "custom_success",
            default_error_port: "custom_error"
          },
          "invalid_return_action" => %Action{
            name: "invalid_return_action",
            display_name: "Invalid Return Action",
            description: "Returns invalid format",
            module: TestInvalidReturnAction,
            input_ports: ["input"],
            output_ports: ["success", "error"],
            default_success_port: "success",
            default_error_port: "error"
          },
          "exception_action" => %Action{
            name: "exception_action",
            display_name: "Exception Action",
            description: "Raises an exception",
            module: TestExceptionAction,
            input_ports: ["input"],
            output_ports: ["success", "error"],
            default_success_port: "success",
            default_error_port: "error"
          },
          "invalid_port_action" => %Action{
            name: "invalid_port_action",
            display_name: "Invalid Port Action",
            description: "Returns non-existent port",
            module: TestInvalidPortAction,
            input_ports: ["input"],
            output_ports: ["success", "error"],
            default_success_port: "success",
            default_error_port: "error"
          }
        }
      }
    end
  end

  setup do
    # Start IntegrationRegistry and register test integration
    {:ok, registry_pid} = IntegrationRegistry.start_link([])
    :ok = IntegrationRegistry.register_integration(TestIntegration)

    on_exit(fn ->
      if Process.alive?(registry_pid) do
        GenServer.stop(registry_pid)
      end
    end)

    :ok
  end

  describe "execute_node/3" do
    test "uses proper execution ID from context" do
      node = %Node{
        id: "test-exec-id",
        custom_id: "exec_id_test",
        name: "Execution ID Test",
        type: :action,
        integration_name: "test",
        action_name: "success_action",
        input_map: %{"test" => "data"},
        output_ports: ["success", "error"],
        input_ports: ["input"]
      }

      # Use a unique execution ID
      unique_execution_id = Base.encode16("exec-" <> :crypto.strong_rand_bytes(8))

      execution = Execution.new("wf_1", 1, "graph_executor", %{})
      execution = Execution.start(execution)
      execution = %{execution | id: unique_execution_id}
      execution = Execution.rebuild_runtime(execution, %{})
      routed_input = %{}

      assert {:ok, node_execution, _updated_execution} = NodeExecutor.execute_node(node, execution, routed_input)

      # Verify the node execution has its own unique ID (different from execution_id)
      assert is_binary(node_execution.id)
      # Generated ID length
      assert byte_size(node_execution.id) == 16
      # Node execution ID ≠ workflow execution ID
      assert node_execution.id != unique_execution_id

      # Verify the node execution is properly linked to the workflow execution
      assert node_execution.execution_id == unique_execution_id
      assert node_execution.node_id == "test-exec-id"
      assert node_execution.status == :completed

      # Verify the execution ID is not hardcoded
      refute node_execution.execution_id == "exec-id"
    end

    test "each node execution gets unique ID even within same workflow execution" do
      node1 = %Node{
        id: "test-node-1",
        custom_id: "unique_test_1",
        name: "Unique Test 1",
        type: :action,
        integration_name: "test",
        action_name: "success_action",
        input_map: %{"test" => "data1"},
        output_ports: ["success", "error"],
        input_ports: ["input"]
      }

      node2 = %Node{
        id: "test-node-2",
        custom_id: "unique_test_2",
        name: "Unique Test 2",
        type: :action,
        integration_name: "test",
        action_name: "success_action",
        input_map: %{"test" => "data2"},
        output_ports: ["success", "error"],
        input_ports: ["input"]
      }

      # Same workflow execution ID for both nodes
      shared_execution_id = Base.encode16("exec-" <> :crypto.strong_rand_bytes(8))

      execution = Execution.new("wf_1", 1, "graph_executor", %{})
      execution = Execution.start(execution)
      execution = %{execution | id: shared_execution_id}
      execution = Execution.rebuild_runtime(execution, %{})
      routed_input = %{}

      # Execute both nodes
      assert {:ok, node_execution1, updated_execution} = NodeExecutor.execute_node(node1, execution, routed_input)
      assert {:ok, node_execution2, _final_execution} = NodeExecutor.execute_node(node2, updated_execution, routed_input)

      # Both node executions should have different unique IDs
      assert node_execution1.id != node_execution2.id
      assert is_binary(node_execution1.id)
      assert is_binary(node_execution2.id)
      assert byte_size(node_execution1.id) == 16
      assert byte_size(node_execution2.id) == 16

      # But both should share the same workflow execution_id
      assert node_execution1.execution_id == shared_execution_id
      assert node_execution2.execution_id == shared_execution_id

      # And they should reference their respective nodes
      assert node_execution1.node_id == "test-node-1"
      assert node_execution2.node_id == "test-node-2"
    end

    test "executes simple node successfully" do
      node = %Node{
        id: "test-1",
        custom_id: "simple_test",
        name: "Simple Test",
        type: :action,
        integration_name: "test",
        action_name: "success_action",
        input_map: %{
          "message" => "hello world"
        },
        output_ports: ["success", "error"],
        input_ports: ["input"]
      }

      execution = Execution.new("wf_1", 1, "graph_executor", %{"user" => "john"})
      execution = Execution.start(execution)
      execution = %{execution | id: "exec-1"}
      execution = Execution.rebuild_runtime(execution, %{})
      routed_input = %{"user" => "john"}

      assert {:ok, node_execution, updated_execution} = NodeExecutor.execute_node(node, execution, routed_input)

      # Check node execution
      assert node_execution.node_id == "test-1"
      assert node_execution.status == :completed
      assert node_execution.output_port == "success"
      assert node_execution.output_data == %{
        message: "success",
        input: %{
          "message" => "hello world"
        }
      }
      assert node_execution.error_data == nil
      assert is_integer(node_execution.duration_ms)
      assert node_execution.retry_count == 0

      # Check execution runtime updates (only stored under custom_id)
      assert updated_execution.__runtime["nodes"]["test-1"] == node_execution.output_data
      assert updated_execution.__runtime["executed_nodes"] == ["test-1"]
    end

    test "handles expression evaluation in input_map" do
      node = %Node{
        id: "test-2",
        custom_id: "expression_test",
        name: "Expression Test",
        type: :action,
        integration_name: "test",
        action_name: "transform_action",
        input_map: %{
          "name" => "$input.user_name",
          "email" => "$input.contact.email",
          "previous_result" => "$nodes.api_call.user_id"
        },
        output_ports: ["success", "error"],
        input_ports: ["input"]
      }

      execution = Execution.new("wf_1", 1, "graph_executor", %{
        "user_name" => "alice",
        "contact" => %{"email" => "alice@example.com"}
      })
      execution = Execution.start(execution)
      execution = %{execution | id: "exec-2"}
      execution = Execution.rebuild_runtime(execution, %{})
      # Simulate api_call node already completed
      execution = %{execution | __runtime: Map.put(execution.__runtime, "nodes", %{"api_call" => %{"user_id" => 123}})}
      routed_input = %{
        "user_name" => "alice",
        "contact" => %{"email" => "alice@example.com"}
      }

      assert {:ok, node_execution, _updated_execution} = NodeExecutor.execute_node(node, execution, routed_input)

      # Check that expressions were evaluated
      expected_input = %{
        "name" => "alice",
        "email" => "alice@example.com",
        "previous_result" => 123
      }

      # Check that expressions were evaluated correctly in the output
      assert node_execution.output_data.original == expected_input
      assert node_execution.output_data.uppercase_name == "ALICE"
    end

    test "handles action errors with default error port" do
      node = %Node{
        id: "test-3",
        custom_id: "error_test",
        name: "Error Test",
        type: :action,
        integration_name: "test",
        action_name: "error_action",
        input_map: %{},
        output_ports: ["success", "error"],
        input_ports: ["input"]
      }

      execution = Execution.new("wf_1", 1, "graph_executor", %{})
      execution = Execution.start(execution)
      execution = %{execution | id: "exec-3"}
      execution = Execution.rebuild_runtime(execution, %{})
      routed_input = %{}

      assert {:error, {reason, node_execution}} = NodeExecutor.execute_node(node, execution, routed_input)

      # Check error reason (now a map)
      assert reason["type"] == "action_error"
      assert reason["error"] == "something went wrong"
      assert reason["port"] == "error"

      # Check node execution
      assert node_execution.status == :failed
      assert node_execution.node_id == "test-3"
      assert node_execution.error_data == reason
      assert node_execution.output_data == nil
      assert node_execution.output_port == nil
    end

    test "handles explicit port returns" do
      node = %Node{
        id: "test-4",
        custom_id: "explicit_port_test",
        name: "Explicit Port Test",
        type: :action,
        integration_name: "test",
        action_name: "explicit_port_action",
        input_map: %{
          "should_succeed" => true
        },
        output_ports: ["custom_success", "custom_error"],
        input_ports: ["input"]
      }

      execution = Execution.new("wf_1", 1, "graph_executor", %{})
      execution = Execution.start(execution)
      execution = %{execution | id: "exec-4"}
      execution = Execution.rebuild_runtime(execution, %{})
      routed_input = %{}

      assert {:ok, node_execution, _updated_execution} = NodeExecutor.execute_node(node, execution, routed_input)

      assert node_execution.output_port == "custom_success"
      assert node_execution.output_data == %{result: "explicit success"}
      assert node_execution.status == :completed
    end

    test "handles explicit port errors" do
      node = %Node{
        id: "test-5",
        custom_id: "explicit_error_test",
        name: "Explicit Error Test",
        type: :action,
        integration_name: "test",
        action_name: "explicit_port_action",
        input_map: %{
          "should_succeed" => false
        },
        output_ports: ["custom_success", "custom_error"],
        input_ports: ["input"]
      }

      execution = Execution.new("wf_1", 1, "graph_executor", %{})
      execution = Execution.start(execution)
      execution = %{execution | id: "exec-5"}
      execution = Execution.rebuild_runtime(execution, %{})
      routed_input = %{}

      assert {:error, {reason, node_execution}} = NodeExecutor.execute_node(node, execution, routed_input)

      # Check error reason (map format)
      assert reason["type"] == "action_error"
      assert reason["error"] == "explicit failure"
      assert reason["port"] == "custom_error"

      assert node_execution.status == :failed
      assert node_execution.error_data == reason
    end

    test "handles invalid action return format" do
      node = %Node{
        id: "test-6",
        custom_id: "invalid_return_test",
        name: "Invalid Return Test",
        type: :action,
        integration_name: "test",
        action_name: "invalid_return_action",
        input_map: %{},
        output_ports: ["success", "error"],
        input_ports: ["input"]
      }

      execution = Execution.new("wf_1", 1, "graph_executor", %{})
      execution = Execution.start(execution)
      execution = %{execution | id: "exec-6"}
      execution = Execution.rebuild_runtime(execution, %{})
      routed_input = %{}

      assert {:error, {reason, node_execution}} = NodeExecutor.execute_node(node, execution, routed_input)

      # Check error reason (map format)
      assert reason["type"] == "invalid_action_return_format"
      assert reason["result"] == "\"direct_string_value\""
      assert String.contains?(reason["message"], "Actions must return")

      assert node_execution.status == :failed
      assert node_execution.error_data == reason
    end

    test "handles action execution exceptions" do
      node = %Node{
        id: "test-7",
        custom_id: "exception_test",
        name: "Exception Test",
        type: :action,
        integration_name: "test",
        action_name: "exception_action",
        input_map: %{},
        output_ports: ["success", "error"],
        input_ports: ["input"]
      }

      execution = Execution.new("wf_1", 1, "graph_executor", %{})
      execution = Execution.start(execution)
      execution = %{execution | id: "exec-7"}
      execution = Execution.rebuild_runtime(execution, %{})
      routed_input = %{}

      assert {:error, {reason, node_execution}} = NodeExecutor.execute_node(node, execution, routed_input)

      # Check error reason (map format)
      assert reason["type"] == "action_execution_failed"
      assert String.contains?(reason["error"], "Test exception")
      assert reason["module"] == TestExceptionAction
      # Note: function field may be nil for Action behavior pattern

      assert node_execution.status == :failed
      assert node_execution.error_data == reason
    end

    test "handles invalid output port" do
      node = %Node{
        id: "test-8",
        custom_id: "invalid_port_test",
        name: "Invalid Port Test",
        type: :action,
        integration_name: "test",
        action_name: "invalid_port_action",
        input_map: %{},
        output_ports: ["success", "error"],
        input_ports: ["input"]
      }

      execution = Execution.new("wf_1", 1, "graph_executor", %{})
      execution = Execution.start(execution)
      execution = %{execution | id: "exec-8"}
      execution = Execution.rebuild_runtime(execution, %{})
      routed_input = %{}

      assert {:error, {reason, node_execution}} = NodeExecutor.execute_node(node, execution, routed_input)

      # Check error reason (map format)
      assert reason["type"] == "invalid_output_port"
      assert reason["port"] == "nonexistent_port"
      assert reason["available_ports"] == ["success", "error"]

      assert node_execution.status == :failed
      assert node_execution.error_data == reason
    end

    test "handles integration not found" do
      node = %Node{
        id: "test-9",
        custom_id: "missing_integration",
        name: "Missing Integration",
        type: :action,
        integration_name: "nonexistent",
        action_name: "some_action",
        input_map: %{},
        output_ports: ["success", "error"],
        input_ports: ["input"]
      }

      execution = Execution.new("wf_1", 1, "graph_executor", %{})
      execution = Execution.start(execution)
      execution = %{execution | id: "exec-9"}
      execution = Execution.rebuild_runtime(execution, %{})
      routed_input = %{}

      assert {:error, {reason, node_execution}} = NodeExecutor.execute_node(node, execution, routed_input)

      # Check error reason (map format)
      assert reason["type"] == "action_not_found"
      assert reason["integration_name"] == "nonexistent"
      assert reason["action_name"] == "some_action"

      assert node_execution.status == :failed
    end

    test "handles action not found" do
      node = %Node{
        id: "test-10",
        custom_id: "missing_action",
        name: "Missing Action",
        type: :action,
        integration_name: "test",
        action_name: "nonexistent_action",
        input_map: %{},
        output_ports: ["success", "error"],
        input_ports: ["input"]
      }

      execution = Execution.new("wf_1", 1, "graph_executor", %{})
      execution = Execution.start(execution)
      execution = %{execution | id: "exec-10"}
      execution = Execution.rebuild_runtime(execution, %{})
      routed_input = %{}

      assert {:error, {reason, node_execution}} = NodeExecutor.execute_node(node, execution, routed_input)

      # Check error reason (map format)
      assert reason["type"] == "action_not_found"
      assert reason["integration_name"] == "test"
      assert reason["action_name"] == "nonexistent_action"

      assert node_execution.status == :failed
    end

    test "handles complex expression evaluation with wildcards and filtering" do
      node = %Node{
        id: "test-11",
        custom_id: "complex_expressions",
        name: "Complex Expressions",
        type: :action,
        integration_name: "test",
        action_name: "success_action",
        input_map: %{
          "all_emails" => "$nodes.users.*.email",
          "admin_emails" => "$nodes.users.{role: \"admin\"}.email",
          "first_user" => "$nodes.users[0].name",
          "order_id" => "$input.order.id"
        },
        output_ports: ["success", "error"],
        input_ports: ["input"]
      }

      execution = Execution.new("wf_1", 1, "graph_executor", %{
        "order" => %{"id" => "ORD-123"}
      })
      execution = Execution.start(execution)
      execution = %{execution | id: "exec-11"}
      execution = Execution.rebuild_runtime(execution, %{})
      # Simulate users node already completed
      execution = %{execution | __runtime: Map.put(execution.__runtime, "nodes", %{
        "users" => [
          %{"name" => "Alice", "email" => "alice@test.com", "role" => "admin"},
          %{"name" => "Bob", "email" => "bob@test.com", "role" => "user"},
          %{"name" => "Carol", "email" => "carol@test.com", "role" => "admin"}
        ]
      })}
      routed_input = %{
        "order" => %{"id" => "ORD-123"}
      }

      assert {:ok, node_execution, _updated_execution} = NodeExecutor.execute_node(node, execution, routed_input)

      expected_input = %{
        "all_emails" => ["alice@test.com", "bob@test.com", "carol@test.com"],
        "admin_emails" => ["alice@test.com", "carol@test.com"],
        "first_user" => "Alice",
        "order_id" => "ORD-123"
      }

      # Check that expressions were evaluated correctly in the output
      assert node_execution.output_data.input == expected_input
      assert node_execution.status == :completed
    end
  end

  describe "prepare_input/3" do
    test "evaluates expressions correctly" do
      node = %Node{
        id: "test",
        input_map: %{
          "simple" => "$input.name",
          "nested" => "$input.user.email",
          "from_nodes" => "$nodes.prev_step.result"
        }
      }

      execution = Execution.new("wf_1", 1, "graph_executor", %{
        "name" => "john",
        "user" => %{"email" => "john@example.com"}
      })
      execution = Execution.start(execution)
      execution = %{execution | id: "exec-test"}
      execution = Execution.rebuild_runtime(execution, %{})
      # Simulate prev_step node already completed
      execution = %{execution | __runtime: Map.put(execution.__runtime, "nodes", %{
        "prev_step" => %{"result" => "success"}
      })}
      routed_input = %{
        "name" => "john",
        "user" => %{"email" => "john@example.com"}
      }

      assert {:ok, prepared} = NodeExecutor.prepare_input(node, execution, routed_input)

      assert prepared == %{
               "simple" => "john",
               "nested" => "john@example.com",
               "from_nodes" => "success"
             }
    end

    test "handles missing expression data gracefully" do
      node = %Node{
        id: "test",
        input_map: %{
          "missing" => "$input.nonexistent.field"
        }
      }

      execution = Execution.new("wf_1", 1, "graph_executor", %{})
      execution = Execution.start(execution)
      execution = %{execution | id: "exec-test"}
      execution = Execution.rebuild_runtime(execution, %{})
      routed_input = %{}

      assert {:ok, prepared} = NodeExecutor.prepare_input(node, execution, routed_input)
      assert prepared == %{
               "missing" => nil
             }
    end

    test "handles expression evaluation errors" do
      # This would test cases where ExpressionEngine itself fails
      # For now, we'll test with invalid input_map structure
      node = %Node{
        id: "test",
        input_map: %{
          "test" => "$invalid..expression"
        }
      }

      execution = Execution.new("wf_1", 1, "graph_executor", %{})
      execution = Execution.start(execution)
      execution = %{execution | id: "exec-test"}
      execution = Execution.rebuild_runtime(execution, %{})
      routed_input = %{}

      # Most invalid expressions just return nil, but we can test edge cases
      assert {:ok, prepared} = NodeExecutor.prepare_input(node, execution, routed_input)
      assert prepared == %{
        "test" => nil
      }
    end
  end

  # Note: update_context/3 functionality is now handled internally by NodeExecutor
  # Context updates happen automatically when execute_node/3 completes successfully

  describe "get_action/1" do
    test "successfully retrieves action from registry" do
      node = %Node{
        integration_name: "test",
        action_name: "success_action"
      }

      assert {:ok, action} = NodeExecutor.get_action(node)
      assert action.name == "success_action"
      assert action.module == TestSuccessAction
      assert action.module == TestSuccessAction
    end

    test "handles integration not found" do
      node = %Node{
        integration_name: "nonexistent",
        action_name: "some_action"
      }

      assert {:error, reason} = NodeExecutor.get_action(node)
      assert reason["type"] == "action_not_found"
      assert reason["integration_name"] == "nonexistent"
      assert reason["action_name"] == "some_action"
    end

    test "handles action not found in existing integration" do
      node = %Node{
        integration_name: "test",
        action_name: "nonexistent_action"
      }

      assert {:error, reason} = NodeExecutor.get_action(node)
      assert reason["type"] == "action_not_found"
      assert reason["integration_name"] == "test"
      assert reason["action_name"] == "nonexistent_action"
    end
  end

  describe "build_expression_context/2" do
    test "builds correct expression context" do
      execution = Execution.new("wf_1", 1, "graph_executor", %{"user_id" => 123})
      execution = Execution.start(execution)
      execution = %{execution | id: "exec-test"}
      execution = Execution.rebuild_runtime(execution, %{"api_key" => "secret"})
      # Simulate step1 node already completed
      execution = %{execution | __runtime: Map.put(execution.__runtime, "nodes", %{
        "step1" => %{"result" => "data"}
      })}

      # This tests the private function indirectly through prepare_input
      node = %Node{
        id: "test",
        input_map: %{
          "from_input" => "$input.user_id",
          "from_nodes" => "$nodes.step1.result",
          "from_env" => "$env.api_key"
        }
      }
      routed_input = %{"user_id" => 123}

      assert {:ok, prepared} = NodeExecutor.prepare_input(node, execution, routed_input)

      assert prepared == %{
        "from_input" => 123,
        "from_nodes" => "data",
        "from_env" => "secret"
      }
    end
  end

  describe "JSON serialization compatibility" do
    test "all error data can be serialized to JSON" do
      # Test various error scenarios to ensure JSON compatibility
      test_cases = [
        # Action error
        %{
          "type" => "action_error",
          "error" => "test error",
          "port" => "error"
        },
        # Invalid port
        %{
          "type" => "invalid_output_port",
          "port" => "bad_port",
          "available_ports" => ["success", "error"]
        },
        # Action not found
        %{
          "type" => "action_not_found",
          "integration_name" => "test",
          "action_name" => "missing"
        }
      ]

      for error_data <- test_cases do
        # Should not raise any errors
        assert is_binary(Jason.encode!(error_data))

        # Should round-trip correctly
        json_string = Jason.encode!(error_data)
        assert ^error_data = Jason.decode!(json_string)
      end
    end
  end
end
