defmodule Prana.NodeExecutorTest do
  use ExUnit.Case, async: false

  alias Prana.Action
  alias Prana.Integration
  alias Prana.IntegrationRegistry
  alias Prana.Node
  alias Prana.NodeExecution
  alias Prana.NodeExecutor
  alias Prana.WorkflowExecution

  # Test action modules
  defmodule TestActions do
    # Basic success action
    @moduledoc false
    defmodule BasicSuccess do
      @moduledoc false

      def definition do
        %Action{
          name: "test.basic_success",
          display_name: "Basic Success",
          description: "Basic success action",
          type: :action,
          input_ports: ["input"],
          output_ports: ["output"]
        }
      end

      def execute(input, _context) do
        value = input["value"] || 0
        {:ok, %{result: value * 2}}
      end

      def resume(_params, _context, resume_data) do
        {:ok, resume_data}
      end
    end

    # Action with explicit port
    defmodule ExplicitPort do
      @moduledoc false

      def definition do
        %Action{
          name: "test.explicit_port",
          display_name: "Explicit Port",
          description: "Action with explicit port selection",
          type: :action,
          input_ports: ["input"],
          output_ports: ["premium", "basic", "main"]
        }
      end

      def execute(input, _context) do
        if input["premium"] do
          {:ok, %{status: "premium"}, "premium"}
        else
          {:ok, %{status: "basic"}, "basic"}
        end
      end

      def resume(_params, _context, resume_data) do
        {:ok, resume_data, "resumed"}
      end
    end

    # Action with context
    defmodule WithContext do
      @moduledoc false

      def definition do
        %Action{
          name: "test.with_context",
          display_name: "With Context",
          description: "Action that returns context data",
          type: :action,
          input_ports: ["input"],
          output_ports: ["main"]
        }
      end

      def execute(input, _context) do
        {:ok, %{data: input}, "main", %{processing_time: 100}}
      end

      def resume(_params, _context, resume_data) do
        {:ok, resume_data, "main", %{resumed: true}}
      end
    end

    # Action that returns error
    defmodule ErrorAction do
      @moduledoc false

      def definition do
        %Action{
          name: "test.error_action",
          display_name: "Error Action",
          description: "Action that returns an error",
          type: :action,
          input_ports: ["input"],
          output_ports: ["main"]
        }
      end

      def execute(_input, _context) do
        {:error, "Something went wrong"}
      end

      def resume(_params, _context, _resume_data) do
        {:error, "Resume failed"}
      end
    end

    # Action that returns error with port
    defmodule ErrorWithPort do
      @moduledoc false

      def definition do
        %Action{
          name: "test.error_with_port",
          display_name: "Error With Port",
          description: "Action that returns an error with explicit port",
          type: :action,
          input_ports: ["input"],
          output_ports: ["main", "error", "validation_error"]
        }
      end

      def execute(_input, _context) do
        {:error, "Invalid input", "validation_error"}
      end

      def resume(_params, _context, _resume_data) do
        {:error, "Resume validation failed", "validation_error"}
      end
    end

    # Action that suspends
    defmodule SuspendAction do
      @moduledoc false

      def definition do
        %Action{
          name: "test.suspend_action",
          display_name: "Suspend Action",
          description: "Action that suspends execution",
          type: :action,
          input_ports: ["input"],
          output_ports: ["main", "resumed"]
        }
      end

      def execute(_input, _context) do
        {:suspend, :sub_workflow_sync, %{workflow_id: "child_workflow"}}
      end

      def resume(_params, _context, resume_data) do
        {:ok, resume_data, "resumed"}
      end
    end

    # Action that throws exception
    defmodule ExceptionAction do
      @moduledoc false

      def definition do
        %Action{
          name: "test.exception_action",
          display_name: "Exception Action",
          description: "Action that throws an exception",
          type: :action,
          input_ports: ["input"],
          output_ports: ["main"]
        }
      end

      def execute(_input, _context) do
        raise "Test exception"
      end

      def resume(_params, _context, _resume_data) do
        raise "Resume exception"
      end
    end

    # Action with invalid return format
    defmodule InvalidReturn do
      @moduledoc false

      def definition do
        %Action{
          name: "test.invalid_return",
          display_name: "Invalid Return",
          description: "Action that returns invalid format",
          type: :action,
          input_ports: ["input"],
          output_ports: ["main"]
        }
      end

      def execute(_input, _context) do
        "invalid_return"
      end

      def resume(_params, _context, _resume_data) do
        "invalid_resume_return"
      end
    end

    # Action with dynamic ports
    defmodule DynamicPorts do
      @moduledoc false

      def definition do
        %Action{
          name: "test.dynamic_ports",
          display_name: "Dynamic Ports",
          description: "Action with dynamic output ports",
          type: :action,
          input_ports: ["input"],
          output_ports: ["*"]
        }
      end

      def execute(input, _context) do
        port_name = "dynamic_#{input["type"]}"
        {:ok, %{port_used: port_name}, port_name}
      end

      def resume(_params, _context, resume_data) do
        {:ok, resume_data, "resumed"}
      end
    end

    # Action with invalid port
    defmodule InvalidPort do
      @moduledoc false

      def definition do
        %Action{
          name: "test.invalid_port",
          display_name: "Invalid Port",
          description: "Action that returns invalid port name",
          type: :action,
          input_ports: ["input"],
          output_ports: ["output"]
        }
      end

      def execute(_input, _context) do
        {:ok, %{result: "test"}, "nonexistent_port"}
      end

      def resume(_params, _context, _resume_data) do
        {:ok, %{result: "test"}, "nonexistent_port"}
      end
    end

    # Action with schema validation
    defmodule SchemaValidatedAction do
      @moduledoc false

      def definition do
        %Action{
          name: "test.schema_validated",
          display_name: "Schema Validated Action",
          description: "Action that validates input parameters with schema",
          type: :action,
          input_ports: ["input"],
          output_ports: ["success", "error"],
          params_schema: %{
            "name" => [type: :string, length: [min: 1], required: true],
            "age" => [type: :integer, number: [min: 0, max: 150], required: true],
            "email" => [type: :string]
          }
        }
      end

      def execute(params, _context) do
        {:ok, %{validated: true, received_params: params}, "success"}
      end

      def resume(_params, _context, _resume_data) do
        {:ok, %{resumed: true}, "success"}
      end
    end
  end

  # Test integration for action registration
  defmodule TestIntegration do
    @moduledoc false
    @behaviour Prana.Behaviour.Integration

    def definition do
      %Integration{
        name: "test",
        display_name: "Test Integration",
        description: "Test integration for NodeExecutor tests",
        version: "1.0.0",
        category: "test",
        actions: [
          TestActions.BasicSuccess,
          TestActions.ExplicitPort,
          TestActions.WithContext,
          TestActions.ErrorAction,
          TestActions.ErrorWithPort,
          TestActions.SuspendAction,
          TestActions.ExceptionAction,
          TestActions.InvalidReturn,
          TestActions.DynamicPorts,
          TestActions.InvalidPort,
          TestActions.SchemaValidatedAction
        ]
      }
    end
  end

  setup do
    # Start registry for tests
    {:ok, registry_pid} = IntegrationRegistry.start_link()

    # Register test integration
    :ok = IntegrationRegistry.register_integration(TestIntegration)

    # Create test execution
    execution = %WorkflowExecution{
      id: "test_execution",
      workflow_id: "test_workflow",
      workflow_version: 1,
      execution_mode: :async,
      status: "running",
      vars: %{"api_url" => "https://api.test.com"},
      node_executions: %{},
      __runtime: %{
        "nodes" => %{
          "previous_node" => %{
            "output" => %{"user_id" => 123}
          }
        },
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

    on_exit(fn ->
      if Process.alive?(registry_pid) do
        GenServer.stop(registry_pid)
      end
    end)

    {:ok, execution: execution}
  end

  describe "execute_node/5 - basic execution" do
    test "executes node with simple success", %{execution: execution} do
      node = Node.new("test_node", "test.basic_success", %{"value" => "{{$input.value}}"})
      routed_input = %{"value" => 10}

      assert {:ok, node_execution, _updated_execution} =
               NodeExecutor.execute_node(node, execution, routed_input, %{execution_index: 1, run_index: 0})

      assert node_execution.status == "completed"
      assert node_execution.output_data == %{result: 20}
      assert node_execution.output_port == "output"
      assert node_execution.execution_index == 1
      assert node_execution.run_index == 0
      assert node_execution.params == %{"value" => 10}
      assert is_integer(node_execution.duration_ms)

      # Check updated execution
    end

    test "executes node with explicit port selection", %{execution: execution} do
      node = Node.new("test_node", "test.explicit_port", %{"premium" => true})
      routed_input = %{"premium" => true}

      assert {:ok, node_execution, _updated_execution} =
               NodeExecutor.execute_node(node, execution, routed_input, %{execution_index: 1, run_index: 0})

      assert node_execution.status == "completed"
      assert node_execution.output_data == %{status: "premium"}
      assert node_execution.output_port == "premium"
    end

    test "executes node with context data", %{execution: execution} do
      node = Node.new("test_node", "test.with_context", %{"data" => "test"})
      routed_input = %{"data" => "test"}

      assert {:ok, node_execution, updated_execution} =
               NodeExecutor.execute_node(node, execution, routed_input, %{execution_index: 1, run_index: 0})

      assert node_execution.status == "completed"
      assert node_execution.output_data == %{data: %{"data" => "test"}}
      assert node_execution.output_port == "main"

      # Check that workflow context was updated
      workflow_context = updated_execution.execution_data["context_data"]["workflow"]
      assert workflow_context[:processing_time] == 100
    end

    test "handles action errors", %{execution: execution} do
      node = Node.new("test_node", "test.error_action", %{})
      routed_input = %{}

      assert {:error, {reason, failed_execution}} =
               NodeExecutor.execute_node(node, execution, routed_input, %{execution_index: 1, run_index: 0})

      assert failed_execution.status == "failed"

      assert failed_execution.error_data.code == "action_error"
      assert failed_execution.error_data.details["error"] == "Something went wrong"
      assert failed_execution.error_data.details["port"] == "error"

      assert reason == failed_execution.error_data
    end

    test "handles node suspension", %{execution: execution} do
      node = Node.new("test_node", "test.suspend_action", %{})
      routed_input = %{}

      assert {:suspend, suspended_execution} =
               NodeExecutor.execute_node(node, execution, routed_input, %{execution_index: 1, run_index: 0})

      assert suspended_execution.status == "suspended"
      assert suspended_execution.suspension_type == :sub_workflow_sync
      assert suspended_execution.suspension_data == %{workflow_id: "child_workflow"}
      assert suspended_execution.output_data == nil
      assert suspended_execution.output_port == nil
    end
  end

  describe "execute_node/5 - parameter preparation" do
    test "executes node with nil params", %{execution: execution} do
      node = Node.new("test_node", "test.basic_success", nil)
      routed_input = %{"value" => 10}

      assert {:ok, node_execution, _updated_execution} =
               NodeExecutor.execute_node(node, execution, routed_input, %{execution_index: 1, run_index: 0})

      assert node_execution.params == %{}
    end

    test "executes node with expression params", %{execution: execution} do
      node =
        Node.new("test_node", "test.basic_success", %{
          "value" => "{{$input.amount}}",
          "user_id" => "{{$nodes.previous_node.output.user_id}}",
          "env_var" => "{{$env.environment}}"
        })

      routed_input = %{"amount" => 100}

      assert {:ok, node_execution, _updated_execution} =
               NodeExecutor.execute_node(node, execution, routed_input, %{execution_index: 1, run_index: 0})

      assert node_execution.params == %{
               "value" => 100,
               "user_id" => 123,
               "env_var" => "test"
             }
    end
  end

  describe "execute_node/5 - action retrieval" do
    test "handles nonexistent integration", %{execution: execution} do
      node = Node.new("test_node", "nonexistent.action", %{})
      routed_input = %{}

      assert {:error, {reason, failed_execution}} =
               NodeExecutor.execute_node(node, execution, routed_input, %{execution_index: 1, run_index: 0})

      assert failed_execution.status == "failed"
      assert reason.code == "action_not_found"
      assert reason.details["action_name"] == "nonexistent.action"
    end

    test "handles nonexistent action", %{execution: execution} do
      node = Node.new("test_node", "test.nonexistent_action", %{})
      routed_input = %{}

      assert {:error, {reason, failed_execution}} =
               NodeExecutor.execute_node(node, execution, routed_input, %{execution_index: 1, run_index: 0})

      assert failed_execution.status == "failed"
      assert reason.code == "action_not_found"
      assert reason.details["action_name"] == "test.nonexistent_action"
    end
  end

  describe "execute_node/5 - action execution errors" do
    test "handles action exceptions", %{execution: execution} do
      node = Node.new("test_node", "test.exception_action", %{})
      routed_input = %{}

      assert {:error, {reason, failed_execution}} =
               NodeExecutor.execute_node(node, execution, routed_input, %{execution_index: 1, run_index: 0})

      assert failed_execution.status == "failed"
      assert reason.code == "action_execution_failed"
      assert reason.details["module"] == TestActions.ExceptionAction
      assert reason.details["action"] == "test.exception_action"
      assert String.contains?(reason.details["details"], "RuntimeError")
    end

    test "handles invalid return format", %{execution: execution} do
      node = Node.new("test_node", "test.invalid_return", %{})
      routed_input = %{}

      assert {:error, {reason, failed_execution}} =
               NodeExecutor.execute_node(node, execution, routed_input, %{execution_index: 1, run_index: 0})

      assert failed_execution.status == "failed"
      assert reason.code == "invalid_action_return_format"
      assert reason.details["result"] == "\"invalid_return\""
      assert String.contains?(reason.message, "Actions must return")
    end

    test "handles dynamic ports", %{execution: execution} do
      node = Node.new("test_node", "test.dynamic_ports", %{"type" => "premium"})
      routed_input = %{"type" => "premium"}

      assert {:ok, node_execution, _updated_execution} =
               NodeExecutor.execute_node(node, execution, routed_input, %{execution_index: 1, run_index: 0})

      assert node_execution.status == "completed"
      assert node_execution.output_port == "dynamic_premium"
      assert node_execution.output_data == %{port_used: "dynamic_premium"}
    end

    test "handles invalid port names", %{execution: execution} do
      node = Node.new("test_node", "test.invalid_port", %{})
      routed_input = %{}

      assert {:error, {reason, failed_execution}} =
               NodeExecutor.execute_node(node, execution, routed_input, %{execution_index: 1, run_index: 0})

      assert failed_execution.status == "failed"
      assert reason.code == "invalid_output_port"
      assert reason.details["port"] == "nonexistent_port"
      assert reason.details["available_ports"] == ["output"]
    end
  end

  describe "resume_node/4" do
    test "resumes suspended node successfully", %{execution: execution} do
      # Create a suspended node execution
      node = Node.new("test_node", "test.suspend_action", %{})

      # First execute to get suspended state
      {:suspend, suspended_execution} =
        NodeExecutor.execute_node(node, execution, %{}, %{execution_index: 1, run_index: 0})

      # Now resume
      resume_data = %{result: "resumed_successfully"}
      resume_node = Node.new("test_node", "test.suspend_action", %{})

      assert {:ok, completed_execution, _updated_execution} =
               NodeExecutor.resume_node(resume_node, execution, suspended_execution, resume_data)

      assert completed_execution.status == "completed"
      assert completed_execution.output_data == resume_data
      assert completed_execution.output_port == "resumed"
    end

    test "resumes with context data", %{execution: execution} do
      # Create a suspended node execution
      node = Node.new("test_node", "test.with_context", %{})

      suspended_execution = %NodeExecution{
        node_key: "test_node",
        status: "suspended",
        params: %{"original" => "param"},
        suspension_type: :custom,
        suspension_data: %{},
        execution_index: 1,
        run_index: 0
      }

      resume_data = %{result: "resumed_with_context"}

      assert {:ok, completed_execution, updated_execution} =
               NodeExecutor.resume_node(node, execution, suspended_execution, resume_data)

      assert completed_execution.status == "completed"
      assert completed_execution.output_data == resume_data

      # Check that workflow context was updated during resume
      workflow_context = updated_execution.execution_data["context_data"]["workflow"]
      assert workflow_context[:resumed] == true
      assert completed_execution.output_port == "main"
    end

    test "handles resume errors", %{execution: execution} do
      node = Node.new("test_node", "test.error_action", %{})

      suspended_execution = %NodeExecution{
        node_key: "test_node",
        status: "suspended",
        params: %{},
        suspension_type: :custom,
        suspension_data: %{},
        execution_index: 1,
        run_index: 0
      }

      resume_data = %{result: "should_fail"}

      assert {:error, {reason, failed_execution}} =
               NodeExecutor.resume_node(node, execution, suspended_execution, resume_data)

      assert failed_execution.status == "failed"
      assert reason.code == "action_error"
      assert reason.details["error"] == "Resume failed"
    end

    test "handles resume action exceptions", %{execution: execution} do
      node = Node.new("test_node", "test.exception_action", %{})

      suspended_execution = %NodeExecution{
        node_key: "test_node",
        status: "suspended",
        params: %{},
        suspension_type: :custom,
        suspension_data: %{},
        execution_index: 1,
        run_index: 0
      }

      resume_data = %{result: "should_throw"}

      assert {:error, {reason, failed_execution}} =
               NodeExecutor.resume_node(node, execution, suspended_execution, resume_data)

      assert failed_execution.status == "failed"
      assert reason.code == "action_resume_failed"
      assert reason.details["module"] == TestActions.ExceptionAction
      assert reason.details["action"] == "test.exception_action"
    end

    test "handles nonexistent action during resume", %{execution: execution} do
      node = Node.new("test_node", "nonexistent.action", %{})

      suspended_execution = %NodeExecution{
        node_key: "test_node",
        status: "suspended",
        params: %{},
        suspension_type: :custom,
        suspension_data: %{},
        execution_index: 1,
        run_index: 0
      }

      resume_data = %{}

      assert {:error, {reason, failed_execution}} =
               NodeExecutor.resume_node(node, execution, suspended_execution, resume_data)

      assert failed_execution.status == "failed"
      assert reason.code == "action_not_found"
      assert reason.details["action_name"] == "nonexistent.action"
    end
  end

  describe "invoke_action/3" do
    test "invokes action successfully" do
      action = %Action{
        name: "test_action",
        module: TestActions.BasicSuccess,
        output_ports: ["output"]
      }

      input = %{"value" => 5}
      context = %{}

      assert {:ok, result, port} = NodeExecutor.invoke_action(action, input, context)
      assert result == %{result: 10}
      assert port == "output"
    end

    test "handles action exceptions" do
      action = %Action{
        name: "exception_action",
        module: TestActions.ExceptionAction,
        output_ports: ["output"]
      }

      input = %{}
      context = %{}

      assert {:error, reason} = NodeExecutor.invoke_action(action, input, context)
      assert reason.code == "action_execution_failed"
      assert reason.details["module"] == TestActions.ExceptionAction
      assert reason.details["action"] == "exception_action"
    end
  end

  describe "invoke_resume_action/4" do
    test "invokes resume action successfully" do
      action = %Action{
        name: "test_action",
        module: TestActions.ExplicitPort,
        output_ports: ["resumed"]
      }

      params = %{"original" => "param"}
      context = %{}
      resume_data = %{"result" => "resumed"}

      assert {:ok, result, port} = NodeExecutor.invoke_resume_action(action, params, context, resume_data)
      assert result == resume_data
      assert port == "resumed"
    end

    test "handles resume action exceptions" do
      action = %Action{
        name: "exception_action",
        module: TestActions.ExceptionAction,
        output_ports: ["output"]
      }

      params = %{}
      context = %{}
      resume_data = %{}

      assert {:error, reason} = NodeExecutor.invoke_resume_action(action, params, context, resume_data)
      assert reason.code == "action_resume_failed"
      assert reason.details["module"] == TestActions.ExceptionAction
      assert reason.details["action"] == "exception_action"
    end
  end

  describe "process_action_result/2" do
    test "processes basic success result" do
      action = %Action{output_ports: ["output"]}
      result = {:ok, %{data: "test"}}

      assert {:ok, data, port} = NodeExecutor.process_action_result(result, action)
      assert data == %{data: "test"}
      assert port == "output"
    end

    test "processes explicit port result" do
      action = %Action{output_ports: ["premium", "basic"]}
      result = {:ok, %{data: "test"}, "premium"}

      assert {:ok, data, port} = NodeExecutor.process_action_result(result, action)
      assert data == %{data: "test"}
      assert port == "premium"
    end

    test "processes context-aware result" do
      action = %Action{output_ports: ["output"]}
      result = {:ok, %{data: "test"}, %{context: "data"}}

      assert {:ok, data, port, context} = NodeExecutor.process_action_result(result, action)
      assert data == %{data: "test"}
      assert port == "output"
      assert context == %{context: "data"}
    end

    test "processes context-aware result with explicit port" do
      action = %Action{output_ports: ["main"]}
      result = {:ok, %{data: "test"}, "main", %{context: "data"}}

      assert {:ok, data, port, context} = NodeExecutor.process_action_result(result, action)
      assert data == %{data: "test"}
      assert port == "main"
      assert context == %{context: "data"}
    end

    test "processes suspension result" do
      action = %Action{output_ports: ["output"]}
      result = {:suspend, :sub_workflow_sync, %{workflow_id: "child"}}

      assert {:suspend, type, data} = NodeExecutor.process_action_result(result, action)
      assert type == :sub_workflow_sync
      assert data == %{workflow_id: "child"}
    end

    test "processes error result" do
      action = %Action{output_ports: ["output", "error"]}
      result = {:error, "test_error"}

      assert {:error, error} = NodeExecutor.process_action_result(result, action)
      assert error.code == "action_error"
      assert error.details["error"] == "test_error"
      assert error.details["port"] == "error"
    end

    test "handles dynamic ports" do
      action = %Action{output_ports: ["*"]}
      result = {:ok, %{data: "test"}, "dynamic_port"}

      assert {:ok, data, port} = NodeExecutor.process_action_result(result, action)
      assert data == %{data: "test"}
      assert port == "dynamic_port"
    end

    test "handles invalid port names" do
      action = %Action{output_ports: ["output"]}
      result = {:ok, %{data: "test"}, "invalid_port"}

      assert {:error, error} = NodeExecutor.process_action_result(result, action)
      assert error.code == "invalid_output_port"
      assert error.details["port"] == "invalid_port"
      assert error.details["available_ports"] == ["output"]
    end

    test "handles invalid return format" do
      action = %Action{output_ports: ["output"]}
      result = "invalid_format"

      assert {:error, error} = NodeExecutor.process_action_result(result, action)
      assert error.code == "invalid_action_return_format"
      assert error.details["result"] == "\"invalid_format\""
      assert String.contains?(error.message, "Actions must return")
    end
  end

  describe "context building" do
    test "builds proper expression context", %{execution: execution} do
      node =
        Node.new("test_node", "test.basic_success", %{
          "input_value" => "{{$input.value}}",
          "node_data" => "{{$nodes.previous_node.output.user_id}}",
          "env_data" => "{{$env.environment}}",
          "var_data" => "{{$vars.api_url}}",
          "workflow_id" => "{{$workflow.id}}",
          "execution_id" => "{{$execution.id}}"
        })

      routed_input = %{"value" => 42}

      assert {:ok, node_execution, _updated_execution} =
               NodeExecutor.execute_node(node, execution, routed_input, %{execution_index: 1, run_index: 0})

      assert node_execution.params == %{
               "input_value" => 42,
               "node_data" => 123,
               "env_data" => "test",
               "var_data" => "https://api.test.com",
               "workflow_id" => "test_workflow",
               "execution_id" => "test_execution"
             }
    end
  end

  describe "execution indices" do
    test "properly sets execution and run indices", %{execution: execution} do
      node = Node.new("test_node", "test.basic_success", %{})
      routed_input = %{"value" => 10}

      assert {:ok, node_execution, _updated_execution} =
               NodeExecutor.execute_node(node, execution, routed_input, %{execution_index: 5, run_index: 2})

      assert node_execution.execution_index == 5
      assert node_execution.run_index == 2
    end
  end

  describe "schema validation" do
    test "validates parameters successfully with valid data", %{execution: execution} do
      node = %Node{
        key: "schema_test_node",
        type: "test.schema_validated",
        params: %{
          "name" => "John Doe",
          "age" => 25,
          "email" => "john@example.com"
        }
      }

      routed_input = %{"main" => %{}}

      assert {:ok, node_execution, _updated_execution} =
               NodeExecutor.execute_node(node, execution, routed_input)

      assert node_execution.status == "completed"
      assert node_execution.output_data[:validated] == true
      assert node_execution.output_data[:received_params]["name"] == "John Doe"
      assert node_execution.output_data[:received_params]["age"] == 25
      assert node_execution.output_data[:received_params]["email"] == "john@example.com"
    end

    test "validates parameters with template expressions", %{execution: execution} do
      node = %Node{
        key: "schema_test_node",
        type: "test.schema_validated",
        params: %{
          "name" => "{{ $input.user_name }}",
          "age" => "{{ $input.user_age }}",
          "email" => "test@example.com"
        }
      }

      routed_input = %{"user_name" => "Jane Doe", "user_age" => 30}

      assert {:ok, node_execution, _updated_execution} =
               NodeExecutor.execute_node(node, execution, routed_input)

      assert node_execution.status == "completed"
      assert node_execution.output_data[:received_params]["name"] == "Jane Doe"
      assert node_execution.output_data[:received_params]["age"] == 30
    end

    test "rejects parameters missing required fields", %{execution: execution} do
      node = %Node{
        key: "schema_test_node",
        type: "test.schema_validated",
        params: %{
          "name" => "John Doe"
          # Missing required "age" field
        }
      }

      routed_input = %{"main" => %{}}

      assert {:error, {error, node_execution}} =
               NodeExecutor.execute_node(node, execution, routed_input)

      assert error.code == :workflow_error
      assert error.message == "Action parameters validation failed"
      assert node_execution.status == "failed"

      assert %{"age" => ["is required"]} = error.details[:errors]
    end

    test "rejects parameters with invalid types", %{execution: execution} do
      node = %Node{
        key: "schema_test_node",
        type: "test.schema_validated",
        params: %{
          "name" => "John Doe",
          # Invalid type - should be integer
          "age" => "not_a_number"
        }
      }

      routed_input = %{"main" => %{}}

      assert {:error, {error, node_execution}} =
               NodeExecutor.execute_node(node, execution, routed_input)

      assert error.code == :workflow_error
      assert error.message == "Action parameters validation failed"
      assert node_execution.status == "failed"
      assert %{"age" => ["is required"]} = error.details[:errors]
    end

    test "rejects parameters outside valid range", %{execution: execution} do
      node = %Node{
        key: "schema_test_node",
        type: "test.schema_validated",
        params: %{
          "name" => "John Doe",
          # Above maximum of 150
          "age" => 200
        }
      }

      routed_input = %{"main" => %{}}

      assert {:error, {error, node_execution}} =
               NodeExecutor.execute_node(node, execution, routed_input)

      assert error.code == :workflow_error
      assert error.message == "Action parameters validation failed"
      assert node_execution.status == "failed"
    end

    test "validates parameters on resume_node", %{execution: execution} do
      # Create a suspended node execution with valid params
      suspended_node =
        "schema_test_node"
        |> NodeExecution.new(1, 0)
        |> NodeExecution.start()
        |> NodeExecution.suspend(:test_suspend, %{})

      # Set valid params
      suspended_node = %{suspended_node | params: %{"name" => "John Doe", "age" => 25}}

      node = %Node{
        key: "schema_test_node",
        type: "test.schema_validated",
        params: %{}
      }

      assert {:ok, node_execution, _updated_execution} =
               NodeExecutor.resume_node(node, execution, suspended_node, %{})

      assert node_execution.status == "completed"
      assert node_execution.output_data[:resumed] == true
    end

    test "validates parameters on resume_node with invalid params", %{execution: execution} do
      # Create a suspended node execution with invalid params
      suspended_node =
        "schema_test_node"
        |> NodeExecution.new(1, 0)
        |> NodeExecution.start()
        |> NodeExecution.suspend(:test_suspend, %{})

      # Set invalid params (missing required field)
      suspended_node = %{suspended_node | params: %{"name" => "John Doe"}}

      node = %Node{
        key: "schema_test_node",
        type: "test.schema_validated",
        params: %{}
      }

      assert {:error, {error, node_execution}} =
               NodeExecutor.resume_node(node, execution, suspended_node, %{})

      assert error.code == :workflow_error
      assert node_execution.status == "failed"
    end

    test "skips validation for actions without params_schema", %{execution: execution} do
      # Use BasicSuccess which doesn't have params_schema
      node = %Node{
        key: "basic_test_node",
        type: "test.basic_success",
        params: %{
          "any_param" => "any_value",
          "number" => 42
        }
      }

      routed_input = %{"value" => 10}

      assert {:ok, node_execution, _updated_execution} =
               NodeExecutor.execute_node(node, execution, routed_input)

      assert node_execution.status == "completed"
    end
  end
end
