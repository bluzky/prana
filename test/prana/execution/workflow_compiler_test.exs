defmodule Prana.WorkflowCompilerTest do
  use ExUnit.Case, async: false

  alias Prana.Connection
  alias Prana.ExecutionGraph
  alias Prana.IntegrationRegistry
  alias Prana.Node
  alias Prana.TestSupport.TestIntegration
  alias Prana.Workflow
  alias Prana.WorkflowCompiler

  setup_all do
    # Start the integration registry
    {:ok, pid} = IntegrationRegistry.start_link()

    # Register required integrations for tests
    :ok = IntegrationRegistry.register_integration(TestIntegration)

    on_exit(fn ->
      if Process.alive?(pid) do
        GenServer.stop(pid)
      end
    end)

    :ok
  end

  # ============================================================================
  # Test Helpers
  # ============================================================================

  defp create_trigger_node(key, name) do
    Node.new(name, "test", "trigger_action", %{}, key)
  end

  defp create_action_node(key, name) do
    Node.new(name, "test", "simple_action", %{}, key)
  end

  defp create_simple_workflow do
    # webhook -> validate -> save
    workflow = Workflow.new("simple_workflow", "Test workflow")

    webhook = create_trigger_node("webhook", "Webhook")
    validate = create_action_node("validate", "Validate")
    save = create_action_node("save", "Save")

    workflow =
      workflow
      |> Workflow.add_node!(webhook)
      |> Workflow.add_node!(validate)
      |> Workflow.add_node!(save)

    conn1 = Connection.new(webhook.key, "success", validate.key, "input")
    conn2 = Connection.new(validate.key, "success", save.key, "input")

    {:ok, workflow} = Workflow.add_connection(workflow, conn1)
    {:ok, workflow} = Workflow.add_connection(workflow, conn2)
    workflow
  end

  defp create_parallel_workflow do
    # webhook -> [email, log]
    workflow = Workflow.new("parallel_workflow", "Parallel test")

    webhook = create_trigger_node("webhook", "Webhook")
    email = create_action_node("email", "Email")
    log = create_action_node("log", "Log")

    workflow =
      workflow
      |> Workflow.add_node!(webhook)
      |> Workflow.add_node!(email)
      |> Workflow.add_node!(log)

    conn1 = Connection.new(webhook.key, "success", email.key, "input")
    conn2 = Connection.new(webhook.key, "success", log.key, "input")

    {:ok, workflow} = Workflow.add_connection(workflow, conn1)
    {:ok, workflow} = Workflow.add_connection(workflow, conn2)
    workflow
  end

  defp create_multiple_trigger_workflow do
    # [webhook:trigger] -> validate
    # [schedule:trigger] -> validate
    workflow = Workflow.new("multi_trigger_workflow", "Multiple triggers")

    webhook = create_trigger_node("webhook", "Webhook Trigger")
    schedule = create_trigger_node("schedule", "Schedule Trigger")
    validate = create_action_node("validate", "Validate")

    workflow =
      workflow
      |> Workflow.add_node!(webhook)
      |> Workflow.add_node!(schedule)
      |> Workflow.add_node!(validate)

    conn1 = Connection.new(webhook.key, "success", validate.key, "input")
    conn2 = Connection.new(schedule.key, "success", validate.key, "input")

    {:ok, workflow} = Workflow.add_connection(workflow, conn1)
    {:ok, workflow} = Workflow.add_connection(workflow, conn2)
    workflow
  end

  defp create_orphaned_workflow do
    # webhook -> validate (reachable)
    # orphan_a -> orphan_b (unreachable)
    workflow = Workflow.new("orphaned_workflow", "Workflow with orphaned nodes")

    # Main flow
    webhook = create_trigger_node("webhook", "Webhook")
    validate = create_action_node("validate", "Validate")

    # Orphaned flow
    orphan_a = create_action_node("orphan_a", "Orphan A")
    orphan_b = create_action_node("orphan_b", "Orphan B")

    workflow =
      workflow
      |> Workflow.add_node!(webhook)
      |> Workflow.add_node!(validate)
      |> Workflow.add_node!(orphan_a)
      |> Workflow.add_node!(orphan_b)

    # Only connect main flow and separate orphan flow
    conn1 = Connection.new(webhook.key, "success", validate.key, "input")
    conn2 = Connection.new(orphan_a.key, "success", orphan_b.key, "input")

    {:ok, workflow} = Workflow.add_connection(workflow, conn1)
    {:ok, workflow} = Workflow.add_connection(workflow, conn2)
    workflow
  end

  defp create_diamond_dependency_workflow do
    # trigger -> [process_a, process_b] -> final
    # final depends on both process_a and process_b completing
    workflow = Workflow.new("diamond_workflow", "Diamond dependency pattern")

    trigger = create_trigger_node("trigger", "Trigger")
    process_a = create_action_node("process_a", "Process A")
    process_b = create_action_node("process_b", "Process B")
    final = create_action_node("final", "Final Node")

    workflow =
      workflow
      |> Workflow.add_node!(trigger)
      |> Workflow.add_node!(process_a)
      |> Workflow.add_node!(process_b)
      |> Workflow.add_node!(final)

    # Create diamond pattern connections
    conn1 = Connection.new(trigger.key, "success", process_a.key, "input")
    conn2 = Connection.new(trigger.key, "success", process_b.key, "input")
    conn3 = Connection.new(process_a.key, "success", final.key, "input")
    conn4 = Connection.new(process_b.key, "success", final.key, "input")

    {:ok, workflow} = Workflow.add_connection(workflow, conn1)
    {:ok, workflow} = Workflow.add_connection(workflow, conn2)
    {:ok, workflow} = Workflow.add_connection(workflow, conn3)
    {:ok, workflow} = Workflow.add_connection(workflow, conn4)
    workflow
  end

  defp create_multi_port_workflow do
    # webhook -> validate -> [save (success), error_log (error)]
    workflow = Workflow.new("multi_port_workflow", "Multiple output ports")

    webhook = create_trigger_node("webhook", "Webhook")
    validate = create_action_node("validate", "Validate")
    save = create_action_node("save", "Save Data")
    error_log = create_action_node("error_log", "Log Error")

    workflow =
      workflow
      |> Workflow.add_node!(webhook)
      |> Workflow.add_node!(validate)
      |> Workflow.add_node!(save)
      |> Workflow.add_node!(error_log)

    # Connect success and error paths
    conn1 = Connection.new(webhook.key, "success", validate.key, "input")
    conn2 = Connection.new(validate.key, "success", save.key, "input")
    conn3 = Connection.new(validate.key, "error", error_log.key, "input")

    {:ok, workflow} = Workflow.add_connection(workflow, conn1)
    {:ok, workflow} = Workflow.add_connection(workflow, conn2)
    {:ok, workflow} = Workflow.add_connection(workflow, conn3)
    workflow
  end

  defp create_terminal_node_workflow do
    # webhook -> process -> output (no outgoing connections)
    workflow = Workflow.new("terminal_workflow", "Workflow with terminal node")

    webhook = create_trigger_node("webhook", "Webhook")
    process = create_action_node("process", "Process")
    output = create_action_node("output", "Output")

    workflow =
      workflow
      |> Workflow.add_node!(webhook)
      |> Workflow.add_node!(process)
      |> Workflow.add_node!(output)

    # Output node has no outgoing connections
    conn1 = Connection.new(webhook.key, "success", process.key, "input")
    conn2 = Connection.new(process.key, "success", output.key, "input")

    {:ok, workflow} = Workflow.add_connection(workflow, conn1)
    {:ok, workflow} = Workflow.add_connection(workflow, conn2)
    workflow
  end

  # ============================================================================
  # Basic Compilation Tests
  # ============================================================================

  describe "compile/2" do
    test "compiles simple linear workflow" do
      workflow = create_simple_workflow()

      {:ok, %ExecutionGraph{} = graph} = WorkflowCompiler.compile(workflow)

      assert map_size(graph.node_map) == 3
      assert graph.trigger_node_key == "webhook"
      assert map_size(graph.connection_map) == 2
    end

    test "compiles parallel workflow" do
      workflow = create_parallel_workflow()

      {:ok, %ExecutionGraph{} = graph} = WorkflowCompiler.compile(workflow)

      assert map_size(graph.node_map) == 3

      # Webhook should have 2 outgoing connections
      webhook_node = Enum.find(workflow.nodes, &(&1.key == "webhook"))
      connections = Map.get(graph.connection_map, {webhook_node.key, "success"}, [])
      assert length(connections) == 2
    end

    test "builds correct dependency graph" do
      workflow = create_simple_workflow()
      {:ok, graph} = WorkflowCompiler.compile(workflow)

      validate_node = Enum.find(workflow.nodes, &(&1.key == "validate"))
      save_node = Enum.find(workflow.nodes, &(&1.key == "save"))

      # validate depends on webhook, save depends on validate
      assert Map.has_key?(graph.dependency_graph, validate_node.key)
      assert Map.has_key?(graph.dependency_graph, save_node.key)
    end

    test "returns error for empty workflow" do
      workflow = Workflow.new("empty", "Empty workflow")

      assert {:error, :no_trigger_nodes} = WorkflowCompiler.compile(workflow)
    end

    test "returns error when trigger node not found" do
      workflow = create_simple_workflow()

      assert {:error, {:trigger_node_not_found, "nonexistent"}} =
               WorkflowCompiler.compile(workflow, "nonexistent")
    end

    test "handles multiple triggers with specific selection" do
      workflow = create_multiple_trigger_workflow()

      # Compile with webhook trigger
      webhook_node = Enum.find(workflow.nodes, &(&1.key == "webhook"))
      {:ok, graph1} = WorkflowCompiler.compile(workflow, webhook_node.key)
      assert graph1.trigger_node_key == "webhook"

      # Compile with schedule trigger
      schedule_node = Enum.find(workflow.nodes, &(&1.key == "schedule"))
      {:ok, graph2} = WorkflowCompiler.compile(workflow, schedule_node.key)
      assert graph2.trigger_node_key == "schedule"
    end

    test "returns error when node exists but is not a trigger" do
      workflow = create_simple_workflow()
      validate_node = Enum.find(workflow.nodes, &(&1.key == "validate"))

      result = WorkflowCompiler.compile(workflow, validate_node.key)

      # Should be an error because validate node is not a trigger
      assert match?({:error, {:node_not_trigger, _, _}}, result) or
               match?({:error, {:action_lookup_failed, _, _}}, result)
    end

    test "returns error when multiple triggers exist and none specified" do
      workflow = create_multiple_trigger_workflow()

      assert {:error, {:multiple_triggers_found, trigger_names}} =
               WorkflowCompiler.compile(workflow, nil)

      assert is_list(trigger_names)
      assert length(trigger_names) == 2
    end
  end

  # ============================================================================
  # Graph Pruning Tests
  # ============================================================================

  describe "graph pruning" do
    test "prunes unreachable orphaned nodes" do
      workflow = create_orphaned_workflow()

      # Original workflow has 4 nodes
      assert length(workflow.nodes) == 4
      assert length(Workflow.all_connections(workflow)) == 2

      {:ok, graph} = WorkflowCompiler.compile(workflow)

      # Compiled graph should only have reachable nodes (2 nodes)
      assert map_size(graph.node_map) == 2
      assert map_size(graph.connection_map) == 1

      # Should only contain webhook and validate nodes
      node_keys = Map.keys(graph.node_map)
      assert "webhook" in node_keys
      assert "validate" in node_keys
      refute "orphan_a" in node_keys
      refute "orphan_b" in node_keys
    end

    test "keeps all nodes when everything is reachable" do
      workflow = create_simple_workflow()

      # All 3 nodes should be reachable from trigger
      assert length(workflow.nodes) == 3

      {:ok, graph} = WorkflowCompiler.compile(workflow)

      # All nodes should be preserved
      assert map_size(graph.node_map) == 3
      assert map_size(graph.connection_map) == 2
    end
  end

  # ============================================================================
  # Structure Validation Tests
  # ============================================================================

  describe "execution graph structure" do
    test "creates correct node map" do
      workflow = create_simple_workflow()
      {:ok, graph} = WorkflowCompiler.compile(workflow)

      # All nodes should be in the map
      Enum.each(workflow.nodes, fn node ->
        assert Map.has_key?(graph.node_map, node.key)
        assert graph.node_map[node.key] == node
      end)
    end

    test "creates correct connection map" do
      workflow = create_parallel_workflow()
      {:ok, graph} = WorkflowCompiler.compile(workflow)

      webhook_node = Enum.find(workflow.nodes, &(&1.key == "webhook"))

      # Webhook should have connections mapped by port
      assert Map.has_key?(graph.connection_map, {webhook_node.key, "success"})
      connections = graph.connection_map[{webhook_node.key, "success"}]
      assert length(connections) == 2
    end

    test "accurate node count" do
      workflow1 = create_simple_workflow()
      {:ok, graph1} = WorkflowCompiler.compile(workflow1)
      assert map_size(graph1.node_map) == 3

      workflow2 = create_parallel_workflow()
      {:ok, graph2} = WorkflowCompiler.compile(workflow2)
      assert map_size(graph2.node_map) == 3
    end
  end

  # ============================================================================
  # Complex Dependency Tests
  # ============================================================================

  describe "complex dependencies" do
    test "handles diamond dependency pattern" do
      workflow = create_diamond_dependency_workflow()
      {:ok, graph} = WorkflowCompiler.compile(workflow)

      # Final node should depend on both process_a and process_b
      final_node = Enum.find(workflow.nodes, &(&1.key == "final"))
      process_a_node = Enum.find(workflow.nodes, &(&1.key == "process_a"))
      process_b_node = Enum.find(workflow.nodes, &(&1.key == "process_b"))

      final_deps = Map.get(graph.dependency_graph, final_node.key, [])
      assert process_a_node.key in final_deps
      assert process_b_node.key in final_deps
      assert length(final_deps) == 2
    end

    test "waits for all dependencies in diamond pattern" do
      workflow = create_diamond_dependency_workflow()
      {:ok, graph} = WorkflowCompiler.compile(workflow)

      trigger_node = Enum.find(workflow.nodes, &(&1.key == "trigger"))
      process_a_node = Enum.find(workflow.nodes, &(&1.key == "process_a"))
      process_b_node = Enum.find(workflow.nodes, &(&1.key == "process_b"))

      # Initially only trigger ready
      ready = WorkflowCompiler.find_ready_nodes(graph, MapSet.new(), MapSet.new(), MapSet.new())
      assert length(ready) == 1
      assert hd(ready).key == "trigger"

      # After trigger completes, both process_a and process_b ready
      completed = MapSet.new([trigger_node.key])
      ready = WorkflowCompiler.find_ready_nodes(graph, completed, MapSet.new(), MapSet.new())
      assert length(ready) == 2
      ready_keys = Enum.map(ready, & &1.key)
      assert "process_a" in ready_keys
      assert "process_b" in ready_keys

      # After only process_a completes, final should NOT be ready yet
      completed = MapSet.new([trigger_node.key, process_a_node.key])
      ready = WorkflowCompiler.find_ready_nodes(graph, completed, MapSet.new(), MapSet.new())
      ready_keys = Enum.map(ready, & &1.key)
      refute "final" in ready_keys

      # After both process_a and process_b complete, final should be ready
      completed = MapSet.new([trigger_node.key, process_a_node.key, process_b_node.key])
      ready = WorkflowCompiler.find_ready_nodes(graph, completed, MapSet.new(), MapSet.new())
      assert length(ready) == 1
      assert hd(ready).key == "final"
    end

    test "handles node with multiple dependencies correctly" do
      workflow = create_diamond_dependency_workflow()
      {:ok, graph} = WorkflowCompiler.compile(workflow)

      # Verify dependency graph structure
      trigger_node = Enum.find(workflow.nodes, &(&1.key == "trigger"))
      process_a_node = Enum.find(workflow.nodes, &(&1.key == "process_a"))
      process_b_node = Enum.find(workflow.nodes, &(&1.key == "process_b"))
      final_node = Enum.find(workflow.nodes, &(&1.key == "final"))

      # Process nodes should depend only on trigger
      assert graph.dependency_graph[process_a_node.key] == [trigger_node.key]
      assert graph.dependency_graph[process_b_node.key] == [trigger_node.key]

      # Final node should depend on both process nodes
      final_deps = graph.dependency_graph[final_node.key]
      assert length(final_deps) == 2
      assert process_a_node.key in final_deps
      assert process_b_node.key in final_deps
    end
  end

  # ============================================================================
  # Connection Map Edge Cases
  # ============================================================================

  describe "connection map edge cases" do
    test "handles nodes with multiple output ports" do
      workflow = create_multi_port_workflow()
      {:ok, graph} = WorkflowCompiler.compile(workflow)

      validate_node = Enum.find(workflow.nodes, &(&1.key == "validate"))

      # Validate should have both success and error connections
      success_key = {validate_node.key, "success"}
      error_key = {validate_node.key, "error"}

      assert Map.has_key?(graph.connection_map, success_key)
      assert Map.has_key?(graph.connection_map, error_key)

      success_connections = graph.connection_map[success_key]
      error_connections = graph.connection_map[error_key]

      assert length(success_connections) == 1
      assert length(error_connections) == 1

      # Verify they point to correct targets
      save_node = Enum.find(workflow.nodes, &(&1.key == "save"))
      error_log_node = Enum.find(workflow.nodes, &(&1.key == "error_log"))

      assert hd(success_connections).to == save_node.key
      assert hd(error_connections).to == error_log_node.key
    end

    test "handles nodes with no outgoing connections" do
      workflow = create_terminal_node_workflow()
      {:ok, graph} = WorkflowCompiler.compile(workflow)

      output_node = Enum.find(workflow.nodes, &(&1.key == "output"))

      # Output node should have no connections in the map
      success_key = {output_node.key, "success"}
      error_key = {output_node.key, "error"}

      refute Map.has_key?(graph.connection_map, success_key)
      refute Map.has_key?(graph.connection_map, error_key)

      # Should still be in node map though
      assert Map.has_key?(graph.node_map, output_node.key)
    end

    test "handles non-existent port lookups gracefully" do
      workflow = create_simple_workflow()
      {:ok, graph} = WorkflowCompiler.compile(workflow)

      webhook_node = Enum.find(workflow.nodes, &(&1.key == "webhook"))

      # Non-existent ports should return empty lists
      invalid_key = {webhook_node.key, "invalid_port"}
      connections = Map.get(graph.connection_map, invalid_key, [])
      assert length(connections) == 0
    end

    test "groups connections correctly by source node and port" do
      workflow = create_parallel_workflow()
      {:ok, graph} = WorkflowCompiler.compile(workflow)

      webhook_node = Enum.find(workflow.nodes, &(&1.key == "webhook"))
      email_node = Enum.find(workflow.nodes, &(&1.key == "email"))
      log_node = Enum.find(workflow.nodes, &(&1.key == "log"))

      # Webhook success port should have 2 connections
      success_key = {webhook_node.key, "success"}
      connections = graph.connection_map[success_key]
      assert length(connections) == 2

      # Verify target nodes
      target_ids = Enum.map(connections, & &1.to)
      assert email_node.key in target_ids
      assert log_node.key in target_ids

      # Each target should only appear once
      assert length(Enum.uniq(target_ids)) == 2
    end
  end
end
