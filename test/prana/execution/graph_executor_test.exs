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
        id: "node_1",
        custom_id: "test_node",
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
        node_map: %{"node_1" => node},
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
      assert node_execution.node_id == "node_1"
      assert node_execution.output_port == "success"
    end
  end

  describe "find_ready_nodes/3" do
    test "finds nodes with no dependencies" do
      node1 = %Node{id: "node_1", custom_id: "node1"}
      node2 = %Node{id: "node_2", custom_id: "node2"}

      workflow = %Workflow{nodes: [node1, node2], connections: []}

      execution_graph = %ExecutionGraph{
        workflow: workflow,
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
        "active_paths" => %{}
      }

      ready_nodes = GraphExecutor.find_ready_nodes(execution_graph, completed_executions, context)

      assert length(ready_nodes) == 1
      assert hd(ready_nodes).id == "node_1"
    end

    test "finds nodes after dependencies are satisfied" do
      node1 = %Node{id: "node_1", custom_id: "node1"}
      node2 = %Node{id: "node_2", custom_id: "node2"}

      workflow = %Workflow{nodes: [node1, node2], connections: []}

      execution_graph = %ExecutionGraph{
        workflow: workflow,
        dependency_graph: %{
          "node_1" => [],
          # node2 depends on node1
          "node_2" => ["node_1"]
        }
      }

      # node1 is already completed
      completed_executions = %{
        "node_1" => [%NodeExecution{node_id: "node_1", status: :completed, execution_index: 0, run_index: 0}]
      }

      # Updated context structure for conditional branching
      context = %{
        "input" => %{},
        "variables" => %{},
        "metadata" => %{},
        "nodes" => %{"node_1" => %{"status" => "completed"}},
        "executed_nodes" => ["node_1"],
        "active_paths" => %{"node_1_success" => true}
      }

      ready_nodes = GraphExecutor.find_ready_nodes(execution_graph, completed_executions, context)

      assert length(ready_nodes) == 1
      assert hd(ready_nodes).id == "node_2"
    end
  end

  describe "workflow_complete?/2" do
    test "returns true when all nodes are completed" do
      node1 = %Node{id: "node_1"}
      node2 = %Node{id: "node_2"}

      workflow = %Workflow{nodes: [node1, node2], connections: []}

      execution_graph = %ExecutionGraph{
        workflow: workflow,
        dependency_graph: %{
          "node_1" => [],
          "node_2" => []
        },
        connection_map: %{},
        node_map: %{},
        trigger_node: node1,
        total_nodes: 2
      }

      execution = %Execution{
        id: "test_exec",
        workflow_id: "test",
        status: :running,
        vars: %{},
        output_data: nil,
        node_executions: %{
          "node_1" => [%NodeExecution{node_id: "node_1", status: :completed, execution_index: 0, run_index: 0}],
          "node_2" => [%NodeExecution{node_id: "node_2", status: :completed, execution_index: 1, run_index: 0}]
        },
        current_execution_index: 2,
        started_at: DateTime.utc_now(),
        completed_at: nil,
        error_data: nil,
        metadata: %{}
      }

      assert GraphExecutor.workflow_complete?(execution, execution_graph) == true
    end

    test "returns false when some nodes are not completed" do
      node1 = %Node{id: "node_1"}
      node2 = %Node{id: "node_2"}

      workflow = %Workflow{nodes: [node1, node2], connections: []}

      execution_graph = %ExecutionGraph{
        workflow: workflow,
        dependency_graph: %{
          "node_1" => [],
          # node_2 depends on node_1
          "node_2" => ["node_1"]
        },
        connection_map: %{},
        node_map: %{},
        trigger_node: node1,
        total_nodes: 2
      }

      execution = %Execution{
        id: "test_exec",
        workflow_id: "test",
        status: :running,
        vars: %{},
        output_data: nil,
        node_executions: %{
          "node_1" => [%NodeExecution{node_id: "node_1", status: :completed, execution_index: 0, run_index: 0}]
          # node_2 not completed
        },
        current_execution_index: 1,
        started_at: DateTime.utc_now(),
        completed_at: nil,
        error_data: nil,
        metadata: %{}
      }

      assert GraphExecutor.workflow_complete?(execution, execution_graph) == false
    end
  end

  # Note: route_node_output/3 tests removed - routing is now handled internally by NodeExecutor
  # Output routing and context updates are automatically managed by the unified execution architecture
end
