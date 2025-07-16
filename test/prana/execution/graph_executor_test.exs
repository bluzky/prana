defmodule Prana.GraphExecutorTest do
  # Cannot be async due to named GenServer
  use ExUnit.Case, async: false

  alias Prana.ExecutionGraph
  alias Prana.GraphExecutor
  alias Prana.IntegrationRegistry
  alias Prana.Node
  alias Prana.TestSupport.TestIntegration

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

  describe "execute_graph/3" do
    test "executes a simple workflow successfully" do
      # Create a simple workflow with one node
      node = %Node{
        key: "test_node",
        name: "Test Node",
        integration_name: "test",
        action_name: "simple_action",
        params: %{}
      }

      execution_graph = %ExecutionGraph{
        workflow_id: "test_workflow",
        trigger_node_key: "test_node",
        dependency_graph: %{},
        connection_map: %{},
        reverse_connection_map: %{},
        node_map: %{"test_node" => node},
        variables: %{}
      }

      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{},
        metadata: %{}
      }

      # Now that we have registered the test integration, execution should succeed
      result = GraphExecutor.execute_workflow(execution_graph, context)

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
end
