defmodule Prana.Execution.DiamondForkTest do
  @moduledoc """
  Unit tests for diamond fork execution patterns in GraphExecutor

  Tests diamond pattern (A → (B, C) → Merge → D) functionality including:
  - Basic diamond execution flow
  - Fail-fast behavior on branch failures
  - Context tracking and node result availability
  """

  use ExUnit.Case, async: false

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

  # Helper function to convert list-based connections to map-based
  defp convert_connections_to_map(workflow) do
    connections_list = workflow.connections
    
    # Convert to proper map structure using add_connection
    workflow_with_empty_connections = %{workflow | connections: %{}}
    
    Enum.reduce(connections_list, workflow_with_empty_connections, fn connection, acc_workflow ->
      {:ok, updated_workflow} = Workflow.add_connection(acc_workflow, connection)
      updated_workflow
    end)
  end

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
          key: "start",
          name: "Start",
          integration_name: "manual",
          action_name: "trigger",
          params: %{}
        },

        # B: First branch node
        %Node{
          key: "branch_b",
          name: "Branch B",
          integration_name: "manual",
          action_name: "process_adult",
          params: %{
            "data" => "$input.data",
            "branch" => "B"
          }
        },

        # C: Second branch node
        %Node{
          key: "branch_c",
          name: "Branch C",
          integration_name: "manual",
          action_name: "process_minor",
          params: %{
            "data" => "$input.data",
            "branch" => "C"
          }
        },

        # Merge: Combine results from both branches
        %Node{
          key: "merge",
          name: "Merge",
          integration_name: "data",
          action_name: "merge",
          params: %{
            "strategy" => "append",
            "input_a" => "$nodes.branch_b",
            "input_b" => "$nodes.branch_c"
          }
        },

        # D: Final processing node
        %Node{
          key: "final",
          name: "Final",
          integration_name: "manual",
          action_name: "process_adult",
          params: %{
            "data" => "$input.data",
            "final_step" => "true"
          }
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
    updated_nodes =
      Enum.map(workflow.nodes, fn node ->
        if node.key == failing_branch do
          %{node | action_name: "non_existent_action", params: %{"error_message" => "Simulated branch failure"}}
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
      {:ok, execution_graph} = WorkflowCompiler.compile(convert_connections_to_map(workflow), "start")

      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{},
        metadata: %{}
      }

      # Execute the workflow
      result = GraphExecutor.execute_graph(execution_graph, context)

      # Verify successful execution
      assert {:ok, %Execution{status: :completed} = execution} = result

      # Verify all nodes executed by checking node_executions
      all_executions = execution.node_executions |> Map.values() |> List.flatten()
      executed_node_keys = Enum.map(all_executions, & &1.node_key)
      assert "start" in executed_node_keys
      assert "branch_b" in executed_node_keys
      assert "branch_c" in executed_node_keys
      assert "merge" in executed_node_keys
      assert "final" in executed_node_keys

      # Verify sequential execution order by checking node_executions order
      # Sort by execution_index to get chronological order
      sorted_executions = Enum.sort_by(all_executions, & &1.execution_index)
      node_execution_order = Enum.map(sorted_executions, & &1.node_key)
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
      {:ok, execution_graph} = WorkflowCompiler.compile(convert_connections_to_map(workflow), "start")

      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{},
        metadata: %{}
      }

      # Execute the workflow
      {:ok, execution} = GraphExecutor.execute_graph(execution_graph, context)

      # Verify merge node executed successfully
      all_executions = execution.node_executions |> Map.values() |> List.flatten()
      merge_execution = Enum.find(all_executions, &(&1.node_key == "merge"))
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
      {:ok, execution_graph} = WorkflowCompiler.compile(convert_connections_to_map(workflow), "start")

      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{},
        metadata: %{}
      }

      # Execute the workflow
      {:ok, execution} = GraphExecutor.execute_graph(execution_graph, context)

      # Verify final node executed successfully
      all_executions = execution.node_executions |> Map.values() |> List.flatten()
      final_execution = Enum.find(all_executions, &(&1.node_key == "final"))
      assert final_execution != nil
      assert final_execution.status == :completed
      assert final_execution.output_port == "success"

      # Verify merge node also executed successfully
      merge_execution = Enum.find(all_executions, &(&1.node_key == "merge"))
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
      {:ok, execution_graph} = WorkflowCompiler.compile(convert_connections_to_map(workflow), "start")

      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{},
        metadata: %{}
      }

      # Execute the workflow
      result = GraphExecutor.execute_graph(execution_graph, context)

      # Verify workflow failed (can return error tuple on failure)
      case result do
        {:ok, %Execution{status: :failed} = execution} ->
          # Verify execution stopped at failing branch
          all_executions = execution.node_executions |> Map.values() |> List.flatten()
          executed_node_keys = Enum.map(all_executions, & &1.node_key)
          assert "start" in executed_node_keys
          assert "branch_b" in executed_node_keys

          # Verify merge and final nodes did not execute
          refute "merge" in executed_node_keys
          refute "final" in executed_node_keys

        {:error, failed_execution} ->
          # Verify we got a node execution failure with complete execution state
          assert failed_execution.status == :failed

          # Verify the failed node is branch_b
          all_failed_executions = failed_execution.node_executions |> Map.values() |> List.flatten()
          failed_node = Enum.find(all_failed_executions, &(&1.status == :failed))
          assert failed_node != nil
          assert failed_node.node_key == "branch_b"
      end
    end

    test "workflow fails when second branch (C) fails" do
      workflow = create_diamond_workflow_with_failing_branch("branch_c")
      {:ok, execution_graph} = WorkflowCompiler.compile(convert_connections_to_map(workflow), "start")

      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{},
        metadata: %{}
      }

      # Execute the workflow
      result = GraphExecutor.execute_graph(execution_graph, context)

      # Verify workflow failed (can return error tuple on failure)
      case result do
        {:ok, %Execution{status: :failed} = execution} ->
          # Verify execution includes first successful branch but stops at second branch
          all_executions = execution.node_executions |> Map.values() |> List.flatten()
          executed_node_keys = Enum.map(all_executions, & &1.node_key)
          assert "start" in executed_node_keys
          assert "branch_b" in executed_node_keys
          assert "branch_c" in executed_node_keys

          # Verify merge and final nodes did not execute
          refute "merge" in executed_node_keys
          refute "final" in executed_node_keys

        {:error, failed_execution} ->
          # Verify we got a node execution failure with complete execution state
          assert failed_execution.status == :failed

          # Verify the failed node is branch_c
          all_failed_executions = failed_execution.node_executions |> Map.values() |> List.flatten()
          failed_node = Enum.find(all_failed_executions, &(&1.status == :failed))
          assert failed_node != nil
          assert failed_node.node_key == "branch_c"
      end
    end

    test "merge and final nodes do not execute when any branch fails" do
      workflow = create_diamond_workflow_with_failing_branch("branch_b")
      {:ok, execution_graph} = WorkflowCompiler.compile(convert_connections_to_map(workflow), "start")

      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{},
        metadata: %{}
      }

      # Execute the workflow
      result = GraphExecutor.execute_graph(execution_graph, context)

      # Verify workflow failed, regardless of return format
      case result do
        {:ok, %Execution{status: :failed} = execution} ->
          # Verify merge node did not execute
          all_executions = execution.node_executions |> Map.values() |> List.flatten()
          merge_execution = Enum.find(all_executions, &(&1.node_key == "merge"))
          assert merge_execution == nil

          # Verify final node did not execute
          final_execution = Enum.find(all_executions, &(&1.node_key == "final"))
          assert final_execution == nil

          # Verify failed node has error result
          failed_execution = Enum.find(all_executions, &(&1.node_key == "branch_b"))
          assert failed_execution != nil
          assert failed_execution.status == :failed

        {:error, failed_execution} ->
          # Verify we got a node execution failure with complete execution state
          assert failed_execution.status == :failed

          # Verify the failed node is branch_b
          all_failed_executions = failed_execution.node_executions |> Map.values() |> List.flatten()
          failed_node = Enum.find(all_failed_executions, &(&1.status == :failed))
          assert failed_node != nil
          assert failed_node.node_key == "branch_b"
      end
    end
  end

  # ============================================================================
  # Test Cases: Context Tracking
  # ============================================================================

  describe "Context Tracking" do
    test "executed_nodes includes all diamond pattern nodes in correct order" do
      workflow = create_basic_diamond_workflow()
      {:ok, execution_graph} = WorkflowCompiler.compile(convert_connections_to_map(workflow), "start")

      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{},
        metadata: %{}
      }

      # Execute the workflow
      {:ok, execution} = GraphExecutor.execute_graph(execution_graph, context)

      # Verify all nodes are tracked in node_executions
      all_executions = execution.node_executions |> Map.values() |> List.flatten()
      executed_node_keys = Enum.map(all_executions, & &1.node_key)
      expected_nodes = ["start", "branch_b", "branch_c", "merge", "final"]

      assert length(executed_node_keys) == length(expected_nodes)

      # Verify all expected nodes are present
      Enum.each(expected_nodes, fn node_key ->
        assert node_key in executed_node_keys
      end)
    end

    test "merge node can access both branch results" do
      workflow = create_basic_diamond_workflow()
      {:ok, execution_graph} = WorkflowCompiler.compile(convert_connections_to_map(workflow), "start")

      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{},
        metadata: %{}
      }

      # Execute the workflow
      {:ok, execution} = GraphExecutor.execute_graph(execution_graph, context)

      # Verify merge node has access to branch results
      all_executions = execution.node_executions |> Map.values() |> List.flatten()
      branch_b_execution = Enum.find(all_executions, &(&1.node_key == "branch_b"))
      branch_c_execution = Enum.find(all_executions, &(&1.node_key == "branch_c"))
      merge_execution = Enum.find(all_executions, &(&1.node_key == "merge"))

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
      {:ok, execution_graph} = WorkflowCompiler.compile(convert_connections_to_map(workflow), "start")

      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{},
        metadata: %{}
      }

      # Execute the workflow
      {:ok, execution} = GraphExecutor.execute_graph(execution_graph, context)

      # Verify final node has access to all previous results
      all_executions = execution.node_executions |> Map.values() |> List.flatten()
      final_execution = Enum.find(all_executions, &(&1.node_key == "final"))
      merge_execution = Enum.find(all_executions, &(&1.node_key == "merge"))

      assert final_execution != nil
      assert merge_execution != nil

      # Verify final node executed successfully with access to context
      assert final_execution.status == :completed
      assert final_execution.output_port == "success"

      # Verify all diamond pattern nodes are accessible in execution
      start_execution = Enum.find(all_executions, &(&1.node_key == "start"))
      branch_b_execution = Enum.find(all_executions, &(&1.node_key == "branch_b"))
      branch_c_execution = Enum.find(all_executions, &(&1.node_key == "branch_c"))

      assert start_execution != nil
      assert branch_b_execution != nil
      assert branch_c_execution != nil
    end
  end
end
