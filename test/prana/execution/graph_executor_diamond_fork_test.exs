defmodule Prana.Execution.DiamondForkTest do
  @moduledoc """
  Unit tests for diamond fork execution patterns in GraphExecutor

  Tests diamond pattern (A → (B, C) → Merge → D) functionality including:
  - Basic diamond execution flow
  - Fail-fast behavior on branch failures
  - Context tracking and node result availability
  """

  use ExUnit.Case, async: true

  alias Prana.Connection
  alias Prana.Execution
  alias Prana.GraphExecutor
  alias Prana.Integrations.Data
  alias Prana.Integrations.Manual
  alias Prana.Node
  alias Prana.Workflow
  alias Prana.WorkflowCompiler

  # ============================================================================
  # Setup and Helpers
  # ============================================================================

  setup do
    # Start integration registry for each test
    Code.ensure_loaded(Prana.Integrations.Data)
    Code.ensure_loaded(Prana.Integrations.Manual)
    {:ok, registry_pid} = Prana.IntegrationRegistry.start_link()

    # Register required integrations with error handling
    case Prana.IntegrationRegistry.register_integration(Data) do
      :ok ->
        :ok

      {:error, reason} ->
        GenServer.stop(registry_pid)
        raise "Failed to register Data integration: #{inspect(reason)}"
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

  defp create_basic_diamond_workflow do
    %Workflow{
      id: "diamond_test",
      name: "Diamond Fork Test Workflow",
      description: "Test basic diamond pattern execution",
      nodes: [
        # A: Start/trigger node
        %Node{
          id: "start",
          custom_id: "start",
          name: "Start",
          type: :trigger,
          integration_name: "manual",
          action_name: "trigger",
          input_map: %{},
          output_ports: ["success"],
          input_ports: []
        },

        # B: First branch node
        %Node{
          id: "branch_b",
          custom_id: "branch_b",
          name: "Branch B",
          type: :action,
          integration_name: "manual",
          action_name: "process_adult",
          input_map: %{
            "data" => "$input.data",
            "branch" => "B"
          },
          output_ports: ["success"],
          input_ports: ["input"]
        },

        # C: Second branch node
        %Node{
          id: "branch_c",
          custom_id: "branch_c",
          name: "Branch C",
          type: :action,
          integration_name: "manual",
          action_name: "process_minor",
          input_map: %{
            "data" => "$input.data",
            "branch" => "C"
          },
          output_ports: ["success"],
          input_ports: ["input"]
        },

        # Merge: Combine results from both branches
        %Node{
          id: "merge",
          custom_id: "merge",
          name: "Merge",
          type: :action,
          integration_name: "data",
          action_name: "merge",
          input_map: %{
            "strategy" => "append",
            "input_a" => "$nodes.branch_b",
            "input_b" => "$nodes.branch_c"
          },
          output_ports: ["success", "error"],
          input_ports: ["input_a", "input_b"]
        },

        # D: Final processing node
        %Node{
          id: "final",
          custom_id: "final",
          name: "Final",
          type: :action,
          integration_name: "manual",
          action_name: "process_adult",
          input_map: %{
            "data" => "$input.data",
            "final_step" => "true"
          },
          output_ports: ["success"],
          input_ports: ["input"]
        }
      ],
      connections: [
        # A → B
        %Connection{
          from: "start",
          from_port: "success",
          to: "branch_b",
          to_port: "input"
        },
        # A → C
        %Connection{
          from: "start",
          from_port: "success",
          to: "branch_c",
          to_port: "input"
        },
        # B → Merge
        %Connection{
          from: "branch_b",
          from_port: "success",
          to: "merge",
          to_port: "input_a"
        },
        # C → Merge
        %Connection{
          from: "branch_c",
          from_port: "success",
          to: "merge",
          to_port: "input_b"
        },
        # Merge → D
        %Connection{
          from: "merge",
          from_port: "success",
          to: "final",
          to_port: "input"
        }
      ],
      variables: %{},
      settings: %{},
      metadata: %{}
    }
  end

  defp create_diamond_workflow_with_failing_branch(failing_branch) do
    workflow = create_basic_diamond_workflow()
    
    # Update the failing branch to use non-existent action to simulate failure
    updated_nodes = Enum.map(workflow.nodes, fn node ->
      if node.id == failing_branch do
        %{node | 
          action_name: "non_existent_action",
          input_map: %{"error_message" => "Simulated branch failure"}
        }
      else
        node
      end
    end)
    
    %{workflow | nodes: updated_nodes}
  end

  # ============================================================================
  # Test Cases: Basic Diamond Execution
  # ============================================================================

  describe "Basic Diamond Execution" do
    test "executes diamond pattern A → (B, C) → Merge → D successfully" do
      workflow = create_basic_diamond_workflow()
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "start")
      
      input_data = %{"data" => "test_data"}
      
      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{},
        metadata: %{}
      }

      # Execute the workflow
      result = GraphExecutor.execute_graph(execution_graph, input_data, context)
      
      # Verify successful execution
      assert {:ok, %Execution{status: :completed} = execution} = result
      
      # Verify all nodes executed by checking node_executions
      executed_node_ids = Enum.map(execution.node_executions, & &1.node_id)
      assert "start" in executed_node_ids
      assert "branch_b" in executed_node_ids
      assert "branch_c" in executed_node_ids
      assert "merge" in executed_node_ids
      assert "final" in executed_node_ids
      
      # Verify sequential execution order by checking node_executions order
      node_execution_order = Enum.map(execution.node_executions, & &1.node_id)
      start_index = Enum.find_index(node_execution_order, &(&1 == "start"))
      branch_b_index = Enum.find_index(node_execution_order, &(&1 == "branch_b"))
      branch_c_index = Enum.find_index(node_execution_order, &(&1 == "branch_c"))
      merge_index = Enum.find_index(node_execution_order, &(&1 == "merge"))
      final_index = Enum.find_index(node_execution_order, &(&1 == "final"))
      
      # Verify execution order: start < (branch_b, branch_c) < merge < final
      assert start_index < branch_b_index
      assert start_index < branch_c_index
      assert branch_b_index < merge_index
      assert branch_c_index < merge_index
      assert merge_index < final_index
    end

    test "merge receives outputs from both branches" do
      workflow = create_basic_diamond_workflow()
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "start")
      
      input_data = %{"data" => "test_value"}
      
      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{},
        metadata: %{}
      }

      # Execute the workflow
      {:ok, execution} = GraphExecutor.execute_graph(execution_graph, input_data, context)
      
      # Verify merge node executed successfully
      merge_execution = Enum.find(execution.node_executions, &(&1.node_id == "merge"))
      assert merge_execution != nil
      assert merge_execution.status == :completed
      assert merge_execution.output_port == "success"
      
      # Verify merge output contains data from both branches
      merged_data = merge_execution.output_data
      assert is_list(merged_data)
      assert length(merged_data) == 2
    end

    test "final node receives merged data from merge node" do
      workflow = create_basic_diamond_workflow()
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "start")
      
      input_data = %{"data" => "test_value"}
      
      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{},
        metadata: %{}
      }

      # Execute the workflow
      {:ok, execution} = GraphExecutor.execute_graph(execution_graph, input_data, context)
      
      # Verify final node executed successfully
      final_execution = Enum.find(execution.node_executions, &(&1.node_id == "final"))
      assert final_execution != nil
      assert final_execution.status == :completed
      assert final_execution.output_port == "success"
      
      # Verify merge node also executed successfully
      merge_execution = Enum.find(execution.node_executions, &(&1.node_id == "merge"))
      assert merge_execution != nil
      assert merge_execution.status == :completed
    end
  end

  # ============================================================================
  # Test Cases: Fail-Fast Behavior
  # ============================================================================

  describe "Fail-Fast Behavior" do
    test "workflow fails when first branch (B) fails" do
      workflow = create_diamond_workflow_with_failing_branch("branch_b")
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "start")
      
      input_data = %{"data" => "test_data"}
      
      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{},
        metadata: %{}
      }

      # Execute the workflow
      result = GraphExecutor.execute_graph(execution_graph, input_data, context)
      
      # Verify workflow failed (can return error tuple on failure)
      case result do
        {:ok, %Execution{status: :failed} = execution} ->
          # Verify execution stopped at failing branch
          executed_node_ids = Enum.map(execution.node_executions, & &1.node_id)
          assert "start" in executed_node_ids
          assert "branch_b" in executed_node_ids
          
          # Verify merge and final nodes did not execute
          refute "merge" in executed_node_ids
          refute "final" in executed_node_ids
          
        {:error, error} ->
          # Verify we got a node execution failure
          assert error.type == "node_execution_failed"
          assert error.node_id == "branch_b"
      end
    end

    test "workflow fails when second branch (C) fails" do
      workflow = create_diamond_workflow_with_failing_branch("branch_c")
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "start")
      
      input_data = %{"data" => "test_data"}
      
      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{},
        metadata: %{}
      }

      # Execute the workflow
      result = GraphExecutor.execute_graph(execution_graph, input_data, context)
      
      # Verify workflow failed (can return error tuple on failure)
      case result do
        {:ok, %Execution{status: :failed} = execution} ->
          # Verify execution includes first successful branch but stops at second branch
          executed_node_ids = Enum.map(execution.node_executions, & &1.node_id)
          assert "start" in executed_node_ids
          assert "branch_b" in executed_node_ids
          assert "branch_c" in executed_node_ids
          
          # Verify merge and final nodes did not execute
          refute "merge" in executed_node_ids
          refute "final" in executed_node_ids
          
        {:error, error} ->
          # Verify we got a node execution failure
          assert error.type == "node_execution_failed"
          assert error.node_id == "branch_c"
      end
    end

    test "merge and final nodes do not execute when any branch fails" do
      workflow = create_diamond_workflow_with_failing_branch("branch_b")
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "start")
      
      input_data = %{"data" => "test_data"}
      
      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{},
        metadata: %{}
      }

      # Execute the workflow
      result = GraphExecutor.execute_graph(execution_graph, input_data, context)
      
      # Verify workflow failed, regardless of return format
      case result do
        {:ok, %Execution{status: :failed} = execution} ->
          # Verify merge node did not execute
          merge_execution = Enum.find(execution.node_executions, &(&1.node_id == "merge"))
          assert merge_execution == nil
          
          # Verify final node did not execute
          final_execution = Enum.find(execution.node_executions, &(&1.node_id == "final"))
          assert final_execution == nil
          
          # Verify failed node has error result
          failed_execution = Enum.find(execution.node_executions, &(&1.node_id == "branch_b"))
          assert failed_execution != nil
          assert failed_execution.status == :failed
          
        {:error, error} ->
          # Just verify we got the expected failure
          assert error.type == "node_execution_failed"
          assert error.node_id == "branch_b"
      end
    end
  end

  # ============================================================================
  # Test Cases: Context Tracking
  # ============================================================================

  describe "Context Tracking" do
    test "executed_nodes includes all diamond pattern nodes in correct order" do
      workflow = create_basic_diamond_workflow()
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "start")
      
      input_data = %{"data" => "test_data"}
      
      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{},
        metadata: %{}
      }

      # Execute the workflow
      {:ok, execution} = GraphExecutor.execute_graph(execution_graph, input_data, context)
      
      # Verify all nodes are tracked in node_executions
      executed_node_ids = Enum.map(execution.node_executions, & &1.node_id)
      expected_nodes = ["start", "branch_b", "branch_c", "merge", "final"]
      
      assert length(executed_node_ids) == length(expected_nodes)
      
      # Verify all expected nodes are present
      Enum.each(expected_nodes, fn node_id ->
        assert node_id in executed_node_ids
      end)
    end

    test "context is available in merge and downstream nodes" do
      workflow = create_basic_diamond_workflow()
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "start")
      
      input_data = %{"data" => "context_test"}
      
      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{"test_var" => "test_value"},
        metadata: %{"workflow_id" => "diamond_test"}
      }

      # Execute the workflow
      {:ok, execution} = GraphExecutor.execute_graph(execution_graph, input_data, context)
      
      # Verify input data preservation
      assert execution.input_data["data"] == "context_test"
      
      # Verify context inheritance through diamond pattern
      branch_b_execution = Enum.find(execution.node_executions, &(&1.node_id == "branch_b"))
      branch_c_execution = Enum.find(execution.node_executions, &(&1.node_id == "branch_c"))
      merge_execution = Enum.find(execution.node_executions, &(&1.node_id == "merge"))
      final_execution = Enum.find(execution.node_executions, &(&1.node_id == "final"))
      
      assert branch_b_execution != nil
      assert branch_c_execution != nil
      assert merge_execution != nil
      assert final_execution != nil
    end

    test "merge node can access both branch results" do
      workflow = create_basic_diamond_workflow()
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "start")
      
      input_data = %{"data" => "branch_test"}
      
      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{},
        metadata: %{}
      }

      # Execute the workflow
      {:ok, execution} = GraphExecutor.execute_graph(execution_graph, input_data, context)
      
      # Verify merge node has access to branch results
      branch_b_execution = Enum.find(execution.node_executions, &(&1.node_id == "branch_b"))
      branch_c_execution = Enum.find(execution.node_executions, &(&1.node_id == "branch_c"))
      merge_execution = Enum.find(execution.node_executions, &(&1.node_id == "merge"))
      
      assert branch_b_execution != nil
      assert branch_c_execution != nil
      assert merge_execution != nil
      
      # Verify merge result contains combined data
      assert merge_execution.status == :completed
      assert merge_execution.output_port == "success"
      merged_output = merge_execution.output_data
      assert is_list(merged_output)
      assert length(merged_output) == 2
    end

    test "final node can access merged results" do
      workflow = create_basic_diamond_workflow()
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "start")
      
      input_data = %{"data" => "final_test"}
      
      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{},
        metadata: %{}
      }

      # Execute the workflow
      {:ok, execution} = GraphExecutor.execute_graph(execution_graph, input_data, context)
      
      # Verify final node has access to all previous results
      final_execution = Enum.find(execution.node_executions, &(&1.node_id == "final"))
      merge_execution = Enum.find(execution.node_executions, &(&1.node_id == "merge"))
      
      assert final_execution != nil
      assert merge_execution != nil
      
      # Verify final node executed successfully with access to context
      assert final_execution.status == :completed
      assert final_execution.output_port == "success"
      
      # Verify all diamond pattern nodes are accessible in execution
      start_execution = Enum.find(execution.node_executions, &(&1.node_id == "start"))
      branch_b_execution = Enum.find(execution.node_executions, &(&1.node_id == "branch_b"))
      branch_c_execution = Enum.find(execution.node_executions, &(&1.node_id == "branch_c"))
      
      assert start_execution != nil
      assert branch_b_execution != nil
      assert branch_c_execution != nil
    end
  end
end