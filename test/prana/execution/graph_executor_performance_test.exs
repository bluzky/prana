defmodule Prana.GraphExecutorPerformanceTest do
  @moduledoc """
  Performance tests to verify GraphExecutor optimizations.

  Tests the impact of Phase 3.2.5 performance optimizations:
  - O(1) connection lookups using pre-built maps
  - Optimized context management with batch updates
  - Reverse connection map for incoming connection queries
  """

  # Cannot be async due to named GenServer
  use ExUnit.Case, async: false

  alias Prana.Connection
  alias Prana.Execution
  alias Prana.ExecutionGraph
  alias Prana.GraphExecutor
  alias Prana.IntegrationRegistry
  alias Prana.Node
  alias Prana.NodeExecution
  alias Prana.TestSupport.TestIntegration
  alias Prana.Workflow
  alias Prana.WorkflowCompiler
  alias Prana.WorkflowSettings

  describe "performance optimizations" do
    setup do
      # Start the IntegrationRegistry GenServer for testing
      {:ok, registry_pid} = Prana.IntegrationRegistry.start_link()

      # Register test integration
      :ok = IntegrationRegistry.register_integration(TestIntegration)

      on_exit(fn ->
        if Process.alive?(registry_pid) do
          GenServer.stop(registry_pid)
        end
      end)

      :ok
    end

    test "O(1) connection lookups scale with workflow size" do
      # Create a large workflow with many connections to test O(1) performance
      node_count = 100

      # Create nodes in a linear chain: trigger → node1 → node2 → ... → node99
      trigger_node = %Node{
        id: "trigger",
        custom_id: "trigger",
        name: "Trigger Node",
        type: :trigger,
        integration_name: "test",
        action_name: "simple_action",
        input_map: %{},
        output_ports: ["success"],
        input_ports: []
      }

      action_nodes =
        Enum.map(1..(node_count - 1), fn i ->
          %Node{
            id: "node_#{i}",
            custom_id: "node_#{i}",
            name: "Action Node #{i}",
            type: :action,
            integration_name: "test",
            action_name: "simple_action",
            input_map: %{},
            output_ports: ["success"],
            input_ports: ["input"]
          }
        end)

      all_nodes = [trigger_node | action_nodes]

      # Create connections in a linear chain
      connections =
        Enum.map(0..(node_count - 2), fn i ->
          from_id = if i == 0, do: "trigger", else: "node_#{i}"
          to_id = "node_#{i + 1}"

          %Connection{
            from: from_id,
            from_port: "success",
            to: to_id,
            to_port: "input"
          }
        end)

      workflow = %Workflow{
        id: "performance_test_workflow",
        name: "Performance Test Workflow",
        nodes: all_nodes,
        connections: connections,
        variables: %{},
        settings: %WorkflowSettings{},
        metadata: %{}
      }

      # Compile workflow to create optimized ExecutionGraph
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "trigger")

      # Verify optimization maps are created
      assert map_size(execution_graph.connection_map) == node_count - 1
      assert map_size(execution_graph.reverse_connection_map) == node_count - 1
      assert map_size(execution_graph.node_map) == node_count

      # Time the execution to ensure it scales well
      input_data = %{"test" => "data"}

      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{},
        metadata: %{}
      }

      {time_microseconds, result} =
        :timer.tc(fn ->
          GraphExecutor.execute_graph(execution_graph, input_data, context)
        end)

      # Should complete successfully
      assert {:ok, execution} = result
      assert execution.status == :completed
      assert length(execution.node_executions) == node_count

      # Performance assertion: should complete large workflow in reasonable time
      # With O(1) lookups, even 100 nodes should complete quickly
      time_milliseconds = time_microseconds / 1000
      assert time_milliseconds < 1000, "Execution took #{time_milliseconds}ms, expected < 1000ms"
    end

    test "connection map provides O(1) lookups" do
      # Create a node with multiple outgoing connections to test lookup performance
      source_node = %Node{
        id: "source",
        custom_id: "source",
        name: "Source Node",
        type: :trigger,
        integration_name: "test",
        action_name: "simple_action",
        input_map: %{},
        output_ports: ["success"],
        input_ports: []
      }

      # Create 50 target nodes
      target_nodes =
        Enum.map(1..50, fn i ->
          %Node{
            id: "target_#{i}",
            custom_id: "target_#{i}",
            name: "Target Node #{i}",
            type: :action,
            integration_name: "test",
            action_name: "simple_action",
            input_map: %{},
            output_ports: ["success"],
            input_ports: ["input"]
          }
        end)

      # Create connections from source to all targets
      connections =
        Enum.map(1..50, fn i ->
          %Connection{
            from: "source",
            from_port: "success",
            to: "target_#{i}",
            to_port: "input"
          }
        end)

      workflow = %Workflow{
        id: "connection_lookup_test",
        name: "Connection Lookup Test",
        nodes: [source_node | target_nodes],
        connections: connections,
        variables: %{},
        settings: %WorkflowSettings{},
        metadata: %{}
      }

      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "source")

      # Test O(1) connection lookup performance
      lookup_key = {"source", "success"}

      # Time multiple lookups to test consistency
      {time_microseconds, _result} =
        :timer.tc(fn ->
          Enum.each(1..1000, fn _iteration ->
            connections_found = Map.get(execution_graph.connection_map, lookup_key, [])
            assert length(connections_found) == 50
          end)
        end)

      time_per_lookup = time_microseconds / 1000
      assert time_per_lookup < 10, "Average lookup took #{time_per_lookup}μs, expected < 10μs"
    end

    test "reverse connection map provides fast incoming connection queries" do
      # Create a fan-in pattern: multiple sources → single target
      target_node = %Node{
        id: "target",
        custom_id: "target",
        name: "Target Node",
        type: :action,
        integration_name: "test",
        action_name: "simple_action",
        input_map: %{},
        output_ports: ["success"],
        input_ports: ["input"]
      }

      # Create 30 source nodes
      source_nodes =
        Enum.map(1..30, fn i ->
          %Node{
            id: "source_#{i}",
            custom_id: "source_#{i}",
            name: "Source Node #{i}",
            type: :trigger,
            integration_name: "test",
            action_name: "simple_action",
            input_map: %{},
            output_ports: ["success"],
            input_ports: []
          }
        end)

      # Create connections from all sources to target
      connections =
        Enum.map(1..30, fn i ->
          %Connection{
            from: "source_#{i}",
            from_port: "success",
            to: "target",
            to_port: "input"
          }
        end)

      workflow = %Workflow{
        id: "reverse_lookup_test",
        name: "Reverse Lookup Test",
        nodes: [target_node | source_nodes],
        connections: connections,
        variables: %{},
        settings: %WorkflowSettings{},
        metadata: %{}
      }

      # For this test, we'll manually create the execution graph to include all connections
      # since WorkflowCompiler prunes unreachable nodes
      connection_map =
        Enum.group_by(connections, fn conn ->
          {conn.from, conn.from_port}
        end)

      reverse_connection_map = Enum.group_by(connections, fn conn -> conn.to end)

      node_map = Map.new([target_node | source_nodes], fn node -> {node.id, node} end)

      execution_graph = %ExecutionGraph{
        workflow: workflow,
        trigger_node: hd(source_nodes),
        dependency_graph: %{},
        connection_map: connection_map,
        reverse_connection_map: reverse_connection_map,
        node_map: node_map,
        total_nodes: 31
      }

      # Test reverse connection lookup performance
      {time_microseconds, _result} =
        :timer.tc(fn ->
          Enum.each(1..1000, fn _iteration ->
            incoming_connections = Map.get(execution_graph.reverse_connection_map, "target", [])
            assert length(incoming_connections) == 30
          end)
        end)

      time_per_lookup = time_microseconds / 1000
      assert time_per_lookup < 5, "Reverse lookup took #{time_per_lookup}μs, expected < 5μs"
    end

    test "unified execution architecture provides efficient runtime state management" do
      # Create a large execution with many completed nodes
      execution = %Execution{
        id: "perf_test",
        workflow_id: "perf_workflow",
        workflow_version: 1,
        execution_mode: "performance_test",
        status: :running,
        input_data: %{},
        node_executions: [],
        __runtime: nil
      }

      # Create many completed node executions to test performance
      node_executions =
        Enum.map(1..100, fn i ->
          %NodeExecution{
            id: "ne_#{i}",
            execution_id: "perf_test",
            node_id: "node_#{i}",
            status: :completed,
            output_data: %{"result" => "test_#{i}"},
            output_port: "success",
            started_at: DateTime.utc_now()
          }
        end)

      execution = %{execution | node_executions: node_executions}

      # Time runtime state rebuilding operations
      {time_microseconds, _result} =
        :timer.tc(fn ->
          Enum.reduce(1..10, execution, fn _i, acc_execution ->
            Execution.rebuild_runtime(acc_execution, %{})
          end)
        end)

      time_per_rebuild = time_microseconds / 10
      assert time_per_rebuild < 1000, "Runtime rebuild took #{time_per_rebuild}μs, expected < 1000μs"
    end
  end
end
