defmodule Prana.GraphExecutorTest do
  # Cannot be async due to named GenServer
  use ExUnit.Case, async: false

  alias Prana.Execution
  alias Prana.ExecutionGraph
  alias Prana.GraphExecutor
  alias Prana.IntegrationRegistry
  alias Prana.Node
  alias Prana.NodeExecution
  alias Prana.TestSupport.TestIntegration
  alias Prana.Workflow
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

  defp get_first_node_execution(execution) do
    execution |> get_all_node_executions() |> List.first()
  end

  describe "execute_graph/3" do
    setup do
      # Start the IntegrationRegistry GenServer for testing using ExUnit supervision
      {:ok, registry_pid} = Prana.IntegrationRegistry.start_link()

      # Register test integration for the test
      :ok = IntegrationRegistry.register_integration(TestIntegration)

      on_exit(fn ->
        if Process.alive?(registry_pid) do
          GenServer.stop(registry_pid)
        end
      end)

      :ok
    end

    test "executes a simple workflow successfully" do
      # Create a simple workflow with one node
      node = %Node{
        key: "test_node",
        name: "Test Node",
        integration_name: "test",
        action_name: "simple_action",
        params: %{}
      }

      workflow = %Workflow{
        id: "test_workflow",
        name: "Test Workflow",
        nodes: [node],
        connections: [],
        variables: %{},
        settings: %WorkflowSettings{},
        metadata: %{}
      }

      execution_graph = %ExecutionGraph{
        workflow: workflow,
        trigger_node: node,
        dependency_graph: %{},
        connection_map: %{},
        reverse_connection_map: %{},
        node_map: %{"test_node" => node},
        total_nodes: 1
      }

      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{},
        metadata: %{}
      }

      # Now that we have registered the test integration, execution should succeed
      result = GraphExecutor.execute_graph(execution_graph, context)

      # Should return successful execution
      assert {:ok, execution} = result
      assert execution.status == :completed
      assert count_node_executions(execution) == 1

      # Check that the node was executed successfully
      node_execution = get_first_node_execution(execution)
      assert node_execution.status == :completed
      assert node_execution.node_key == "test_node"
      assert node_execution.output_port == "success"
    end
  end

  describe "find_ready_nodes/3" do
    test "finds nodes with no dependencies" do
      node1 = %Node{key: "node_1"}
      node2 = %Node{key: "node_2"}

      workflow = %Workflow{nodes: [node1, node2], connections: []}

      execution_graph = %ExecutionGraph{
        workflow: workflow,
        node_map: %{"node_1" => node1, "node_2" => node2},
        dependency_graph: %{
          "node_1" => [],
          # node2 depends on node1
          "node_2" => ["node_1"]
        }
      }

      completed_executions = %{}

      # Updated context structure for conditional branching
      context = %{
        "input" => %{},
        "variables" => %{},
        "metadata" => %{},
        "nodes" => %{},
        "executed_nodes" => [],
        "active_paths" => %{},
        "active_nodes" => MapSet.new(["node_1", "node_2"])  # Both nodes are active to check
      }

      ready_nodes = GraphExecutor.find_ready_nodes(execution_graph, completed_executions, context)

      assert length(ready_nodes) == 1
      assert hd(ready_nodes).key == "node_1"
    end

    test "finds nodes after dependencies are satisfied" do
      node1 = %Node{key: "node_1"}
      node2 = %Node{key: "node_2"}

      workflow = %Workflow{nodes: [node1, node2], connections: []}

      execution_graph = %ExecutionGraph{
        workflow: workflow,
        node_map: %{"node_1" => node1, "node_2" => node2},
        dependency_graph: %{
          "node_1" => [],
          # node2 depends on node1
          "node_2" => ["node_1"]
        }
      }

      # node1 is already completed
      completed_executions = %{
        "node_1" => [%NodeExecution{node_key: "node_1", status: :completed, execution_index: 0, run_index: 0}]
      }

      # Updated context structure for conditional branching
      context = %{
        "input" => %{},
        "variables" => %{},
        "metadata" => %{},
        "nodes" => %{"node_1" => %{"status" => "completed"}},
        "executed_nodes" => ["node_1"],
        "active_paths" => %{"node_1_success" => true},
        "active_nodes" => MapSet.new(["node_2"])  # node_2 should be active since node_1 completed
      }

      ready_nodes = GraphExecutor.find_ready_nodes(execution_graph, completed_executions, context)

      assert length(ready_nodes) == 1
      assert hd(ready_nodes).key == "node_2"
    end
  end

  # Note: workflow_complete?/2 is no longer needed with active_nodes system
  # Workflow completion is naturally determined by empty active_nodes in execution loop

  # Note: route_node_output/3 tests removed - routing is now handled internally by NodeExecutor
  # Output routing and context updates are automatically managed by the unified execution architecture
end
