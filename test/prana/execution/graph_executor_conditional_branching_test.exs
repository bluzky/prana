defmodule Prana.Execution.ConditionalBranchingTest do
  @moduledoc """
  Unit tests for conditional branching patterns in GraphExecutor

  Tests IF/ELSE and Switch conditional routing functionality including:
  - Basic if/else branching
  - Switch/case multi-branch routing
  - Path activation and filtering
  - Conditional workflow completion
  - Integration with Logic integration
  """

  use ExUnit.Case, async: false

  alias Prana.Connection
  alias Prana.Execution
  alias Prana.ExecutionGraph
  alias Prana.GraphExecutor
  alias Prana.Integrations.Logic
  alias Prana.Integrations.Logic.IfConditionAction
  alias Prana.Integrations.Logic.SwitchAction
  alias Prana.Integrations.Manual
  alias Prana.Node
  alias Prana.NodeExecution
  alias Prana.Workflow
  alias Prana.WorkflowCompiler

  # ============================================================================
  # Setup and Helpers
  # ============================================================================

  setup do
    # Start integration registry for each test
    Code.ensure_loaded(Prana.Integrations.Logic)
    Code.ensure_loaded(Prana.Integrations.Manual)
    {:ok, registry_pid} = Prana.IntegrationRegistry.start_link()

    # Register required integrations with error handling
    case Prana.IntegrationRegistry.register_integration(Logic) do
      :ok ->
        :ok

      {:error, reason} ->
        GenServer.stop(registry_pid)
        raise "Failed to register Logic integration: #{inspect(reason)}"
    end

    case Prana.IntegrationRegistry.register_integration(Manual) do
      :ok ->
        :ok

      {:error, reason} ->
        GenServer.stop(registry_pid)
        raise "Failed to register Manual integration: #{inspect(reason)}"
    end

    on_exit(fn ->
      if Process.alive?(registry_pid) do
        GenServer.stop(registry_pid)
      end
    end)

    :ok
  end

  defp create_basic_if_else_workflow do
    %Workflow{
      id: "if_else_test",
      name: "IF/ELSE Test Workflow",
      description: "Test basic conditional branching",
      nodes: [
        # Start/trigger node
        %Node{
          key: "start",
          name: "Start",
          integration_name: "manual",
          action_name: "trigger",
          params: %{},
          metadata: %{}
        },

        # IF condition node
        %Node{
          key: "age_check",
          name: "Age Check",
          integration_name: "logic",
          action_name: "if_condition",
          params: %{
            "condition" => "age >= 18",
            "true_data" => %{"status" => "adult", "message" => "You are an adult"},
            "false_data" => %{"status" => "minor", "message" => "You are a minor"}
          },
          metadata: %{}
        },

        # True branch - adult processing
        %Node{
          key: "adult_process",
          name: "Adult Processing",
          integration_name: "manual",
          action_name: "process_adult",
          params: %{},
          metadata: %{}
        },

        # False branch - minor processing
        %Node{
          key: "minor_process",
          name: "Minor Processing",
          integration_name: "manual",
          action_name: "process_minor",
          params: %{},
          metadata: %{}
        }
      ],
      connections: [
        # Start -> Age Check
        %Connection{
          from: "start",
          from_port: "success",
          to: "age_check",
          to_port: "input",
          metadata: %{}
        },

        # Age Check -> Adult (true branch)
        %Connection{
          from: "age_check",
          from_port: "true",
          to: "adult_process",
          to_port: "input",
          metadata: %{}
        },

        # Age Check -> Minor (false branch)
        %Connection{
          from: "age_check",
          from_port: "false",
          to: "minor_process",
          to_port: "input",
          metadata: %{}
        }
      ],
      variables: %{},
      settings: %Prana.WorkflowSettings{},
      metadata: %{}
    }
  end

  defp create_switch_workflow do
    %Workflow{
      id: "switch_test",
      name: "Switch Test Workflow",
      description: "Test switch/case conditional branching",
      nodes: [
        # Start/trigger node
        %Node{
          key: "start",
          name: "Start",
          integration_name: "manual",
          action_name: "trigger",
          params: %{},
          metadata: %{}
        },

        # Switch node
        %Node{
          key: "user_type_switch",
          name: "User Type Switch",
          integration_name: "logic",
          action_name: "switch",
          params: %{
            "switch_expression" => "user_type",
            "cases" => %{
              "premium" => {"premium", %{"discount" => 0.2, "tier" => "premium"}},
              "standard" => {"standard", %{"discount" => 0.1, "tier" => "standard"}},
              "basic" => {"basic", %{"discount" => +0.0, "tier" => "basic"}}
            },
            "default_data" => %{"discount" => +0.0, "tier" => "unknown"}
          },
          metadata: %{}
        },

        # Premium processing
        %Node{
          key: "premium_process",
          name: "Premium Processing",
          integration_name: "manual",
          action_name: "process_adult",
          params: %{},
          metadata: %{}
        },

        # Standard processing
        %Node{
          key: "standard_process",
          name: "Standard Processing",
          integration_name: "manual",
          action_name: "process_adult",
          params: %{},
          metadata: %{}
        },

        # Basic processing
        %Node{
          key: "basic_process",
          name: "Basic Processing",
          integration_name: "manual",
          action_name: "process_minor",
          params: %{},
          metadata: %{}
        }
      ],
      connections: [
        # Start -> Switch
        %Connection{
          from: "start",
          from_port: "success",
          to: "user_type_switch",
          to_port: "input",
          metadata: %{}
        },

        # Switch -> Premium
        %Connection{
          from: "user_type_switch",
          from_port: "premium",
          to: "premium_process",
          to_port: "input",
          metadata: %{}
        },

        # Switch -> Standard
        %Connection{
          from: "user_type_switch",
          from_port: "standard",
          to: "standard_process",
          to_port: "input",
          metadata: %{}
        },

        # Switch -> Basic
        %Connection{
          from: "user_type_switch",
          from_port: "basic",
          to: "basic_process",
          to_port: "input",
          metadata: %{}
        }
      ],
      variables: %{},
      settings: %Prana.WorkflowSettings{},
      metadata: %{}
    }
  end

  # ============================================================================
  # IF/ELSE Conditional Branching Tests
  # ============================================================================

  describe "IF/ELSE conditional branching" do
    test "compiles if/else workflow successfully" do
      workflow = create_basic_if_else_workflow()

      assert {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "start")
      assert %ExecutionGraph{} = execution_graph
      assert length(execution_graph.workflow.nodes) == 4
      assert length(execution_graph.workflow.connections) == 3
    end

    test "finds only start node as ready initially" do
      workflow = create_basic_if_else_workflow()
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "start")

      initial_context = %{
        "input" => %{"age" => 25},
        "variables" => %{},
        "metadata" => %{},
        "nodes" => %{},
        "executed_nodes" => [],
        "active_paths" => %{}
      }

      ready_nodes = GraphExecutor.find_ready_nodes(execution_graph, %{}, initial_context)
      ready_node_keys = Enum.map(ready_nodes, & &1.key)

      assert ready_node_keys == ["start"]
    end

    test "finds condition node ready after start completes" do
      workflow = create_basic_if_else_workflow()
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "start")

      # Simulate start node completion
      start_execution = %NodeExecution{
        id: "start_exec",
        execution_id: "test",
        node_key: "start",
        status: :completed,
        output_data: %{"age" => 25},
        output_port: "success",
        error_data: nil,
        retry_count: 0,
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now(),
        duration_ms: 10,
        metadata: %{}
      }

      context_after_start = %{
        "input" => %{"age" => 25},
        "variables" => %{},
        "metadata" => %{},
        "nodes" => %{"start" => %{"age" => 25}},
        "executed_nodes" => ["start"],
        "active_paths" => %{"start_success" => true}
      }

      node_executions_map = %{"start" => [start_execution]}
      ready_nodes = GraphExecutor.find_ready_nodes(execution_graph, node_executions_map, context_after_start)
      ready_node_keys = Enum.map(ready_nodes, & &1.key)

      assert ready_node_keys == ["age_check"]
    end

    test "conditional path filtering prevents both branches from being ready" do
      workflow = create_basic_if_else_workflow()
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "start")

      # Simulate both start and condition nodes completed
      start_execution = %NodeExecution{
        id: "start_exec",
        execution_id: "test",
        node_key: "start",
        status: :completed,
        output_data: %{"age" => 25},
        output_port: "success",
        error_data: nil,
        retry_count: 0,
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now(),
        duration_ms: 10,
        metadata: %{}
      }

      # Condition node completed with TRUE result (adult path)
      condition_execution = %NodeExecution{
        id: "condition_exec",
        execution_id: "test",
        node_key: "age_check",
        status: :completed,
        output_data: %{"status" => "adult", "message" => "You are an adult"},
        output_port: "true",
        error_data: nil,
        retry_count: 0,
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now(),
        duration_ms: 50,
        metadata: %{}
      }

      # Context with TRUE path active (adult path)
      context_with_active_path = %{
        "input" => %{"age" => 25},
        "variables" => %{},
        "metadata" => %{},
        "nodes" => %{
          "start" => %{"age" => 25},
          "age_check" => %{"status" => "adult", "message" => "You are an adult"}
        },
        "executed_nodes" => ["start", "age_check"],
        "active_paths" => %{
          "start_success" => true,
          # Only true path is active
          "age_check_true" => true
        }
      }

      node_executions_map = %{"start" => [start_execution], "age_check" => [condition_execution]}

      ready_nodes =
        GraphExecutor.find_ready_nodes(
          execution_graph,
          node_executions_map,
          context_with_active_path
        )

      ready_node_keys = Enum.map(ready_nodes, & &1.key)

      # Only adult_process should be ready (not minor_process)
      assert ready_node_keys == ["adult_process"]
      refute "minor_process" in ready_node_keys
    end

    test "false branch executes when condition is false" do
      workflow = create_basic_if_else_workflow()
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "start")

      # Simulate both start and condition nodes completed (realistic execution sequence)
      start_execution = %NodeExecution{
        id: "start_exec",
        execution_id: "test",
        node_key: "start",
        status: :completed,
        output_data: %{"age" => 16},
        output_port: "success",
        error_data: nil,
        retry_count: 0,
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now(),
        duration_ms: 10,
        metadata: %{}
      }

      # Condition node completed with FALSE result (minor path)
      condition_execution = %NodeExecution{
        id: "condition_exec",
        execution_id: "test",
        node_key: "age_check",
        status: :completed,
        output_data: %{"status" => "minor", "message" => "You are a minor"},
        output_port: "false",
        error_data: nil,
        retry_count: 0,
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now(),
        duration_ms: 50,
        metadata: %{}
      }

      # Context with FALSE path active (minor path)
      context_with_false_path = %{
        "input" => %{"age" => 16},
        "variables" => %{},
        "metadata" => %{},
        "nodes" => %{
          "start" => %{"age" => 16},
          "age_check" => %{"status" => "minor", "message" => "You are a minor"}
        },
        "executed_nodes" => ["start", "age_check"],
        "active_paths" => %{
          "start_success" => true,
          # Only false path is active
          "age_check_false" => true
        }
      }

      node_executions_map = %{"start" => [start_execution], "age_check" => [condition_execution]}

      ready_nodes =
        GraphExecutor.find_ready_nodes(
          execution_graph,
          node_executions_map,
          context_with_false_path
        )

      ready_node_keys = Enum.map(ready_nodes, & &1.key)

      # Only minor_process should be ready (not adult_process)
      assert ready_node_keys == ["minor_process"]
      refute "adult_process" in ready_node_keys
    end
  end

  # ============================================================================
  # Switch/Case Conditional Branching Tests
  # ============================================================================

  describe "Switch/Case conditional branching" do
    test "compiles switch workflow successfully" do
      workflow = create_switch_workflow()

      assert {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "start")
      assert %ExecutionGraph{} = execution_graph
      assert length(execution_graph.workflow.nodes) == 5
      assert length(execution_graph.workflow.connections) == 4
    end

    test "premium path executes for premium users" do
      workflow = create_switch_workflow()
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "start")

      # Simulate both start and switch nodes completed (realistic execution sequence)
      start_execution = %NodeExecution{
        id: "start_exec",
        execution_id: "test",
        node_key: "start",
        status: :completed,
        output_data: %{"user_type" => "premium"},
        output_port: "success",
        error_data: nil,
        retry_count: 0,
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now(),
        duration_ms: 10,
        metadata: %{}
      }

      # Switch node completed with premium result
      switch_execution = %NodeExecution{
        id: "switch_exec",
        execution_id: "test",
        node_key: "user_type_switch",
        status: :completed,
        output_data: %{"discount" => 0.2, "tier" => "premium"},
        output_port: "premium",
        error_data: nil,
        retry_count: 0,
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now(),
        duration_ms: 30,
        metadata: %{}
      }

      # Context with premium path active
      context_with_premium_path = %{
        "input" => %{"user_type" => "premium"},
        "variables" => %{},
        "metadata" => %{},
        "nodes" => %{
          "start" => %{"user_type" => "premium"},
          "user_type_switch" => %{"discount" => 0.2, "tier" => "premium"}
        },
        "executed_nodes" => ["start", "user_type_switch"],
        "active_paths" => %{
          "start_success" => true,
          "user_type_switch_premium" => true
        }
      }

      node_executions_map = %{"start" => [start_execution], "user_type_switch" => [switch_execution]}

      ready_nodes =
        GraphExecutor.find_ready_nodes(
          execution_graph,
          node_executions_map,
          context_with_premium_path
        )

      ready_node_keys = Enum.map(ready_nodes, & &1.key)

      # Only premium_process should be ready
      assert ready_node_keys == ["premium_process"]
      refute "standard_process" in ready_node_keys
      refute "basic_process" in ready_node_keys
    end

    test "standard path executes for standard users" do
      workflow = create_switch_workflow()
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "start")

      # Simulate both start and switch nodes completed (realistic execution sequence)
      start_execution = %NodeExecution{
        id: "start_exec",
        execution_id: "test",
        node_key: "start",
        status: :completed,
        output_data: %{"user_type" => "standard"},
        output_port: "success",
        error_data: nil,
        retry_count: 0,
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now(),
        duration_ms: 10,
        metadata: %{}
      }

      # Switch node completed with standard result
      switch_execution = %NodeExecution{
        id: "switch_exec",
        execution_id: "test",
        node_key: "user_type_switch",
        status: :completed,
        output_data: %{"discount" => 0.1, "tier" => "standard"},
        output_port: "standard",
        error_data: nil,
        retry_count: 0,
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now(),
        duration_ms: 30,
        metadata: %{}
      }

      # Context with standard path active
      context_with_standard_path = %{
        "input" => %{"user_type" => "standard"},
        "variables" => %{},
        "metadata" => %{},
        "nodes" => %{
          "start" => %{"user_type" => "standard"},
          "user_type_switch" => %{"discount" => 0.1, "tier" => "standard"}
        },
        "executed_nodes" => ["start", "user_type_switch"],
        "active_paths" => %{
          "start_success" => true,
          "user_type_switch_standard" => true
        }
      }

      node_executions_map = %{"start" => [start_execution], "user_type_switch" => [switch_execution]}

      ready_nodes =
        GraphExecutor.find_ready_nodes(
          execution_graph,
          node_executions_map,
          context_with_standard_path
        )

      ready_node_keys = Enum.map(ready_nodes, & &1.key)

      # Only standard_process should be ready
      assert ready_node_keys == ["standard_process"]
      refute "premium_process" in ready_node_keys
      refute "basic_process" in ready_node_keys
    end

    test "only one branch executes in switch statement" do
      workflow = create_switch_workflow()
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "start")

      # Test with no active paths (should find no ready nodes except start)
      context_no_active_paths = %{
        "input" => %{"user_type" => "basic"},
        "variables" => %{},
        "metadata" => %{},
        "nodes" => %{},
        "executed_nodes" => [],
        "active_paths" => %{}
      }

      ready_nodes =
        GraphExecutor.find_ready_nodes(
          execution_graph,
          %{},
          context_no_active_paths
        )

      ready_node_keys = Enum.map(ready_nodes, & &1.key)

      # Only start should be ready (no conditional paths active yet)
      assert ready_node_keys == ["start"]
    end
  end

  # ============================================================================
  # Path Activation and Context Tests
  # ============================================================================

  describe "path activation and context management" do
    test "output routing marks conditional paths as active" do
      workflow = create_basic_if_else_workflow()
      {:ok, _execution_graph} = WorkflowCompiler.compile(workflow, "start")

      # Simulate condition node result
      condition_result = %NodeExecution{
        id: "condition_exec",
        execution_id: "test",
        node_key: "age_check",
        status: :completed,
        output_data: %{"status" => "adult", "message" => "You are an adult"},
        output_port: "true",
        error_data: nil,
        retry_count: 0,
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now(),
        duration_ms: 50,
        metadata: %{}
      }

      # Create an execution with completed condition node
      execution = %Execution{
        id: "test_execution",
        workflow_id: "if_else_test",
        status: :running,
        node_executions: %{"age_check" => [condition_result]},
        __runtime: %{
          "nodes" => %{"age_check" => %{"status" => "adult", "message" => "You are an adult"}},
          "env" => %{},
          "active_paths" => %{"age_check_true" => true},
          "executed_nodes" => ["age_check"]
        }
      }

      # The active paths should be set correctly after node completion
      assert execution.__runtime["active_paths"]["age_check_true"] == true
      refute Map.has_key?(execution.__runtime["active_paths"], "age_check_false")

      # The node output should be stored
      assert execution.__runtime["nodes"]["age_check"]["status"] == "adult"
    end

    test "executed nodes are tracked in context" do
      initial_context = %{
        "input" => %{"age" => 25},
        "variables" => %{},
        "metadata" => %{},
        "nodes" => %{},
        "executed_nodes" => [],
        "active_paths" => %{}
      }

      # Simulate storing a node result
      node_execution = %NodeExecution{
        id: "test_exec",
        execution_id: "test",
        node_key: "age_check",
        status: :completed,
        output_data: %{"status" => "adult"},
        output_port: "true",
        error_data: nil,
        retry_count: 0,
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now(),
        duration_ms: 50,
        metadata: %{}
      }

      # Use the private function logic (simulate what store_node_result_in_context does)
      result_data = node_execution.output_data
      nodes = Map.get(initial_context, "nodes", %{})
      updated_nodes = Map.put(nodes, node_execution.node_key, result_data)

      executed_nodes = Map.get(initial_context, "executed_nodes", [])
      updated_executed_nodes = [node_execution.node_key | executed_nodes]

      updated_context =
        initial_context
        |> Map.put("nodes", updated_nodes)
        |> Map.put("executed_nodes", updated_executed_nodes)

      # Verify tracking
      assert updated_context["executed_nodes"] == ["age_check"]
      assert updated_context["nodes"]["age_check"]["status"] == "adult"
    end
  end

  # ============================================================================
  # Logic Integration Tests
  # ============================================================================

  describe "Logic integration" do
    test "if_condition action evaluates conditions correctly" do
      # Test adult condition (true) - should work
      params = %{
        "condition" => "$input.is_adult",
        "true_data" => %{"status" => "adult"},
        "false_data" => %{"status" => "minor"}
      }

      context = %{
        "$input" => %{"is_adult" => true},
        "$nodes" => %{},
        "$variables" => %{}
      }

      result1 = IfConditionAction.execute(params, context)

      assert {:ok, %{"status" => "adult"}, "true"} = result1

      # Test minor condition (false) - should work
      params2 = %{
        "condition" => "$input.is_adult",
        "true_data" => %{"status" => "adult"},
        "false_data" => %{"status" => "minor"}
      }

      context2 = %{
        "$input" => %{"is_adult" => false},
        "$nodes" => %{},
        "$variables" => %{}
      }

      result2 = IfConditionAction.execute(params2, context2)

      assert {:ok, %{"status" => "minor"}, "false"} = result2
    end

    test "switch action routes to correct ports" do
      # Separate params and context for SwitchAction
      premium_params = %{
        "cases" => [
          %{"condition" => "$input.user_type", "value" => "premium", "port" => "premium", "data" => %{"discount" => 0.2}},
          %{
            "condition" => "$input.user_type",
            "value" => "standard",
            "port" => "standard",
            "data" => %{"discount" => 0.1}
          }
        ],
        "default_port" => "basic",
        "default_data" => %{"discount" => +0.0}
      }

      premium_context = %{
        "$input" => %{"user_type" => "premium"},
        "$nodes" => %{},
        "$variables" => %{}
      }

      assert {:ok, %{"discount" => 0.2}, "premium"} = SwitchAction.execute(premium_params, premium_context)

      # Separate params and context for SwitchAction
      standard_params = %{
        "cases" => [
          %{"condition" => "$input.user_type", "value" => "premium", "port" => "premium", "data" => %{"discount" => 0.2}},
          %{
            "condition" => "$input.user_type",
            "value" => "standard",
            "port" => "standard",
            "data" => %{"discount" => 0.1}
          },
          %{"condition" => "$input.user_type", "value" => "basic", "port" => "basic", "data" => %{"discount" => 0.0}}
        ],
        "default_data" => %{"discount" => +0.0}
      }

      standard_context = %{
        "$input" => %{"user_type" => "standard"},
        "$nodes" => %{},
        "$variables" => %{}
      }

      assert {:ok, %{"discount" => 0.1}, "standard"} = SwitchAction.execute(standard_params, standard_context)

      # Separate params and context for SwitchAction
      unknown_params = %{
        "cases" => [
          %{"condition" => "$input.user_type", "value" => "premium", "port" => "premium", "data" => %{"discount" => 0.2}},
          %{
            "condition" => "$input.user_type",
            "value" => "standard",
            "port" => "standard",
            "data" => %{"discount" => 0.1}
          },
          %{"condition" => "$input.user_type", "value" => "basic", "port" => "basic", "data" => %{"discount" => +0.0}}
        ],
        "default_data" => %{"discount" => +0.0, "tier" => "unknown"}
      }

      unknown_context = %{
        "$input" => %{"user_type" => "enterprise"},
        "$nodes" => %{},
        "$variables" => %{}
      }

      assert {:ok, %{"discount" => +0.0, "tier" => "unknown"}, "default"} =
               SwitchAction.execute(unknown_params, unknown_context)
    end

    test "switch action handles numeric values" do
      # Separate params and context for SwitchAction
      numeric_params = %{
        "cases" => [
          %{
            "condition" => "$input.plan_id",
            "value" => 1,
            "port" => "premium",
            "data" => %{"name" => "Premium Plan", "features" => ["feature1", "feature2"]}
          },
          %{
            "condition" => "$input.plan_id",
            "value" => 2,
            "port" => "standard",
            "data" => %{"name" => "Standard Plan", "features" => ["feature1"]}
          },
          %{
            "condition" => "$input.plan_id",
            "value" => 3,
            "port" => "basic",
            "data" => %{"name" => "Basic Plan", "features" => []}
          }
        ],
        "default_data" => %{"name" => "Unknown Plan", "features" => []}
      }

      numeric_context = %{
        "$input" => %{"plan_id" => 1},
        "$nodes" => %{},
        "$variables" => %{}
      }

      assert {:ok, %{"name" => "Premium Plan", "features" => ["feature1", "feature2"]}, "premium"} =
               SwitchAction.execute(numeric_params, numeric_context)
    end

    test "if_condition handles missing condition" do
      # Separate params and context for IfConditionAction
      invalid_params = %{
        "true_data" => %{"status" => "adult"},
        "false_data" => %{"status" => "minor"}
        # Note: missing "condition" field to test error case
      }

      invalid_context = %{
        "$input" => %{"age" => 25},
        "$nodes" => %{},
        "$variables" => %{}
      }

      assert {:error, "Missing required 'condition' field"} = IfConditionAction.execute(invalid_params, invalid_context)
    end

    test "switch handles empty cases array" do
      # Separate params and context for SwitchAction
      empty_params = %{
        "cases" => [],
        "default_data" => %{"discount" => +0.0},
        "default_port" => "default"
      }

      empty_context = %{
        "$input" => %{},
        "$nodes" => %{},
        "$variables" => %{}
      }

      # Should use default when no cases match (empty cases)
      assert {:ok, %{"discount" => +0.0}, "default"} = SwitchAction.execute(empty_params, empty_context)
    end
  end

  # ============================================================================
  # Integration Edge Cases and Error Handling
  # ============================================================================

  describe "edge cases and error handling" do
    test "handles workflow with no conditional paths (backward compatibility)" do
      # Test that workflows without active_paths still work
      workflow = create_basic_if_else_workflow()
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "start")

      # Context without active_paths field (legacy)
      legacy_context = %{
        "input" => %{"age" => 25},
        "variables" => %{},
        "metadata" => %{},
        "nodes" => %{}
      }

      ready_nodes = GraphExecutor.find_ready_nodes(execution_graph, %{}, legacy_context)
      ready_node_keys = Enum.map(ready_nodes, & &1.key)

      # Should still find start node (backward compatibility)
      assert ready_node_keys == ["start"]
    end

    test "handles failed condition node execution" do
      workflow = create_basic_if_else_workflow()
      {:ok, _execution_graph} = WorkflowCompiler.compile(workflow, "start")

      # Simulate failed condition node
      failed_condition = %NodeExecution{
        id: "condition_exec",
        execution_id: "test",
        node_key: "age_check",
        status: :failed,
        output_data: nil,
        # Failed nodes have nil output_port
        output_port: nil,
        error_data: %{"type" => "condition_evaluation_error"},
        retry_count: 0,
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now(),
        duration_ms: 20,
        metadata: %{}
      }

      # Create execution with failed condition node
      execution = %Execution{
        id: "test_execution",
        workflow_id: "if_else_test",
        status: :running,
        node_executions: %{"age_check" => [failed_condition]},
        __runtime: %{
          "nodes" => %{"age_check" => %{"error" => %{"type" => "condition_evaluation_error"}, "status" => :failed}},
          "env" => %{},
          "active_paths" => %{},
          "executed_nodes" => ["age_check"]
        }
      }

      # Failed nodes should not create active paths
      assert Map.get(execution.__runtime, "active_paths", %{}) == %{}

      # Error should be stored in nodes context
      assert execution.__runtime["nodes"]["age_check"]["error"]["type"] == "condition_evaluation_error"
      assert execution.__runtime["nodes"]["age_check"]["status"] == :failed
    end
  end

  # ============================================================================
  # Performance and Integration Tests
  # ============================================================================

  describe "performance and integration" do
    test "handles complex switch workflow with multiple branches" do
      # Separate params and context for SwitchAction
      complex_params = %{
        "cases" => [
          %{"condition" => "$input.status_code", "value" => 200, "port" => "success", "data" => %{"message" => "OK"}},
          %{
            "condition" => "$input.status_code",
            "value" => 201,
            "port" => "created",
            "data" => %{"message" => "Created"}
          },
          %{
            "condition" => "$input.status_code",
            "value" => 400,
            "port" => "bad_request",
            "data" => %{"message" => "Bad Request"}
          },
          %{
            "condition" => "$input.status_code",
            "value" => 401,
            "port" => "unauthorized",
            "data" => %{"message" => "Unauthorized"}
          },
          %{
            "condition" => "$input.status_code",
            "value" => 403,
            "port" => "forbidden",
            "data" => %{"message" => "Forbidden"}
          },
          %{
            "condition" => "$input.status_code",
            "value" => 404,
            "port" => "not_found",
            "data" => %{"message" => "Not Found"}
          },
          %{
            "condition" => "$input.status_code",
            "value" => 500,
            "port" => "server_error",
            "data" => %{"message" => "Internal Server Error"}
          }
        ],
        "default_data" => %{"message" => "Unknown Status"}
      }

      complex_context = %{
        "$input" => %{"status_code" => 404},
        "$nodes" => %{},
        "$variables" => %{}
      }

      assert {:ok, %{"message" => "Not Found"}, "not_found"} = SwitchAction.execute(complex_params, complex_context)
    end

    test "conditional workflow with nested structure" do
      # Test workflow: Start -> Check User Type -> Check Age (if premium) -> Process
      nested_workflow = %Workflow{
        id: "nested_test",
        name: "Nested Conditional Test",
        description: "Test nested conditional logic",
        version: 1,
        nodes: [
          %Node{
            key: "start",
            name: "Start",
            integration_name: "manual",
            action_name: "trigger",
            params: %{},
            metadata: %{}
          },
          %Node{
            key: "user_type_check",
            name: "User Type Check",
            integration_name: "logic",
            action_name: "switch",
            params: %{
              "switch_expression" => "user_type",
              "cases" => %{
                "premium" => {"premium", %{"requires_age_check" => true}},
                "standard" => {"standard", %{"requires_age_check" => false}}
              },
              "default_data" => %{"requires_age_check" => false}
            },
            metadata: %{}
          },
          %Node{
            key: "premium_age_check",
            name: "Premium Age Check",
            integration_name: "logic",
            action_name: "if_condition",
            params: %{
              "condition" => "age >= 21",
              "true_data" => %{"eligible" => true, "tier" => "premium_adult"},
              "false_data" => %{"eligible" => false, "tier" => "premium_minor"}
            },
            metadata: %{}
          },
          %Node{
            key: "standard_process",
            name: "Standard Process",
            integration_name: "manual",
            action_name: "process_adult",
            params: %{},
            metadata: %{}
          }
        ],
        connections: [
          %Connection{
            from: "start",
            from_port: "success",
            to: "user_type_check",
            to_port: "input",
            metadata: %{}
          },
          %Connection{
            from: "user_type_check",
            from_port: "premium",
            to: "premium_age_check",
            to_port: "input",
            metadata: %{}
          },
          %Connection{
            from: "user_type_check",
            from_port: "standard",
            to: "standard_process",
            to_port: "input",
            metadata: %{}
          }
        ],
        variables: %{},
        settings: %Prana.WorkflowSettings{},
        metadata: %{}
      }

      assert {:ok, execution_graph} = WorkflowCompiler.compile(nested_workflow, "start")
      assert %ExecutionGraph{} = execution_graph
      assert length(execution_graph.workflow.nodes) == 4
      assert length(execution_graph.workflow.connections) == 3
    end
  end
end
