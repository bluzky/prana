defmodule Prana.GraphExecutorBranchFollowingTest do
  @moduledoc """
  Tests to verify that GraphExecutor follows branches to completion rather than executing in batches.

  The key behavioral change is:
  - OLD: Find all ready nodes → execute all in batch → route all outputs → repeat
  - NEW: Find ready nodes → select one node → execute it → route its output → repeat

  This ensures that branches are followed to completion before switching to other branches.
  """

  # Cannot be async due to named GenServer
  use ExUnit.Case, async: false

  alias Prana.Connection
  alias Prana.GraphExecutor
  alias Prana.IntegrationRegistry
  alias Prana.Node
  alias Prana.TestSupport.TestIntegration
  alias Prana.Workflow
  alias Prana.WorkflowCompiler
  alias Prana.WorkflowSettings

  # Helper functions for handling map-based node_executions
  defp get_all_node_executions(execution) do
    case execution.node_executions do
      node_executions_map when is_map(node_executions_map) ->
        node_executions_map
        |> Enum.flat_map(fn {_node_id, executions} -> executions end)
        |> Enum.sort_by(& &1.execution_index)

      node_executions_list when is_list(node_executions_list) ->
        node_executions_list
    end
  end

  defp count_node_executions(execution) do
    execution |> get_all_node_executions() |> length()
  end

  describe "branch following execution" do
    setup do
      # Start the IntegrationRegistry GenServer for testing
      {:ok, registry_pid} = Prana.IntegrationRegistry.start_link()

      # Register test integration and data integration for merge
      :ok = IntegrationRegistry.register_integration(TestIntegration)
      Code.ensure_loaded(Prana.Integrations.Data)
      :ok = IntegrationRegistry.register_integration(Prana.Integrations.Data)

      on_exit(fn ->
        if Process.alive?(registry_pid) do
          GenServer.stop(registry_pid)
        end
      end)

      :ok
    end

    test "follows single branch to completion before switching branches" do
      # Create a diamond pattern: trigger → (branch_a, branch_b) → merge
      # With branch-following, one branch should complete fully before the other starts

      trigger_node = %Node{
        key: "trigger",
        name: "Trigger",
        integration_name: "test",
        action_name: "trigger_action",
        params: %{}
      }

      # Branch A: two sequential nodes
      branch_a1 = %Node{
        key: "branch_a1",
        name: "Branch A Step 1",
        integration_name: "test",
        action_name: "simple_action",
        params: %{}
      }

      branch_a2 = %Node{
        key: "branch_a2",
        name: "Branch A Step 2",
        integration_name: "test",
        action_name: "simple_action",
        params: %{}
      }

      # Branch B: two sequential nodes
      branch_b1 = %Node{
        key: "branch_b1",
        name: "Branch B Step 1",
        integration_name: "test",
        action_name: "simple_action",
        params: %{}
      }

      branch_b2 = %Node{
        key: "branch_b2",
        name: "Branch B Step 2",
        integration_name: "test",
        action_name: "simple_action",
        params: %{}
      }

      # Merge node (waits for both branches)
      merge_node = %Node{
        key: "merge",
        name: "Merge",
        integration_name: "data",
        action_name: "merge",
        params: %{}
      }

      connections = [
        # Trigger to both branch starts
        %Connection{
          from: "trigger",
          from_port: "success",
          to: "branch_a1",
          to_port: "input"
        },
        %Connection{
          from: "trigger",
          from_port: "success",
          to: "branch_b1",
          to_port: "input"
        },

        # Branch A sequence
        %Connection{
          from: "branch_a1",
          from_port: "success",
          to: "branch_a2",
          to_port: "input"
        },

        # Branch B sequence
        %Connection{
          from: "branch_b1",
          from_port: "success",
          to: "branch_b2",
          to_port: "input"
        },

        # Both branches to merge
        %Connection{
          from: "branch_a2",
          from_port: "success",
          to: "merge",
          to_port: "input_a"
        },
        %Connection{
          from: "branch_b2",
          from_port: "success",
          to: "merge",
          to_port: "input_b"
        }
      ]

      workflow = %Workflow{
        id: "branch_following_test",
        name: "Branch Following Test",
        nodes: [trigger_node, branch_a1, branch_a2, branch_b1, branch_b2, merge_node],
        connections: connections,
        variables: %{},
        settings: %WorkflowSettings{},
        metadata: %{}
      }

      {:ok, execution_graph} =
        WorkflowCompiler.compile(workflow, "trigger")

      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{},
        metadata: %{}
      }

      # Execute workflow
      {:ok, execution} = GraphExecutor.execute_graph(execution_graph, context)

      # Verify execution completed successfully
      assert execution.status == :completed
      assert count_node_executions(execution) == 6

      # Analyze execution order to verify branch following
      execution_order = Enum.map(get_all_node_executions(execution), & &1.node_key)

      # The trigger should be first
      assert List.first(execution_order) == "trigger"

      # After trigger, one branch should complete before the other starts
      # Due to branch-following, we should see patterns like:
      # trigger → branch_a1 → branch_a2 → branch_b1 → branch_b2 → merge
      # OR
      # trigger → branch_b1 → branch_b2 → branch_a1 → branch_a2 → merge

      trigger_index = Enum.find_index(execution_order, &(&1 == "trigger"))
      a1_index = Enum.find_index(execution_order, &(&1 == "branch_a1"))
      a2_index = Enum.find_index(execution_order, &(&1 == "branch_a2"))
      b1_index = Enum.find_index(execution_order, &(&1 == "branch_b1"))
      b2_index = Enum.find_index(execution_order, &(&1 == "branch_b2"))
      merge_index = Enum.find_index(execution_order, &(&1 == "merge"))

      # Trigger should be first
      assert trigger_index == 0

      # Branch sequences should be maintained (a1 before a2, b1 before b2)
      assert a1_index < a2_index, "Branch A sequence not maintained: a1=#{a1_index}, a2=#{a2_index}"
      assert b1_index < b2_index, "Branch B sequence not maintained: b1=#{b1_index}, b2=#{b2_index}"

      # Merge should be last (after both branches complete)
      assert merge_index == 5

      # With branch following, one complete branch should execute before the other starts
      # This means either:
      # 1. a1, a2 both come before b1, b2
      # 2. b1, b2 both come before a1, a2
      branch_a_complete_before_b_starts = a2_index < b1_index
      branch_b_complete_before_a_starts = b2_index < a1_index

      # One of these should be true (branch following behavior)
      branch_following_detected = branch_a_complete_before_b_starts || branch_b_complete_before_a_starts

      assert branch_following_detected,
             "Branch following not detected. Execution order: #{inspect(execution_order)}. " <>
               "Expected one branch to complete before other starts, but got interleaved execution."
    end

    test "select_node_for_branch_following prioritizes nodes by depth" do
      # Test the node selection logic directly

      # Create nodes
      shallow_node = %Node{key: "shallow"}
      deep_node = %Node{key: "deep"}

      # Context with node depths
      execution_context = %{
        "node_depth" => %{
          "shallow" => 1,
          "deep" => 3
        }
      }

      ready_nodes = [shallow_node, deep_node]

      # Should select the deeper node (higher depth = more advanced in execution)
      selected = GraphExecutor.select_node_for_branch_following(ready_nodes, execution_context)

      assert selected.key == "deep",
             "Expected to select deeper node, but got #{selected.key}"
    end

    test "select_node_for_branch_following handles nodes with same depth" do
      # Test when nodes have the same depth (should select first one)

      node_a = %Node{key: "node_a"}
      node_b = %Node{key: "node_b"}

      # Context with same depth for both nodes
      execution_context = %{
        "node_depth" => %{
          "node_a" => 2,
          "node_b" => 2
        }
      }

      ready_nodes = [node_a, node_b]

      # Should select the first node when depths are equal
      selected = GraphExecutor.select_node_for_branch_following(ready_nodes, execution_context)

      assert selected.key == "node_a",
             "Expected to select first node when depths are equal, but got #{selected.key}"
    end
  end
end
