defmodule Prana.WorkflowCompilerTest do
  use ExUnit.Case, async: false

  alias Prana.Connection
  alias Prana.ExecutionGraph
  alias Prana.Node
  alias Prana.Workflow
  alias Prana.WorkflowCompiler

  # ============================================================================
  # Test Helpers
  # ============================================================================

  defp create_trigger_node(custom_id, name) do
    Node.new(name, :trigger, "webhook", "receive", %{}, custom_id)
  end

  defp create_action_node(custom_id, name) do
    Node.new(name, :action, "test_integration", "process", %{}, custom_id)
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

    conn1 = Connection.new(webhook.id, "success", validate.id, "input")
    conn2 = Connection.new(validate.id, "success", save.id, "input")

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

    conn1 = Connection.new(webhook.id, "success", email.id, "input")
    conn2 = Connection.new(webhook.id, "success", log.id, "input")

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

    conn1 = Connection.new(webhook.id, "success", validate.id, "input")
    conn2 = Connection.new(schedule.id, "success", validate.id, "input")

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
    conn1 = Connection.new(webhook.id, "success", validate.id, "input")
    conn2 = Connection.new(orphan_a.id, "success", orphan_b.id, "input")

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
    conn1 = Connection.new(trigger.id, "success", process_a.id, "input")
    conn2 = Connection.new(trigger.id, "success", process_b.id, "input")
    conn3 = Connection.new(process_a.id, "success", final.id, "input")
    conn4 = Connection.new(process_b.id, "success", final.id, "input")

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
    conn1 = Connection.new(webhook.id, "success", validate.id, "input")
    conn2 = Connection.new(validate.id, "success", save.id, "input")
    conn3 = Connection.new(validate.id, "error", error_log.id, "input")

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
    conn1 = Connection.new(webhook.id, "success", process.id, "input")
    conn2 = Connection.new(process.id, "success", output.id, "input")

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

      assert graph.total_nodes == 3
      assert graph.trigger_node.custom_id == "webhook"
      assert length(graph.workflow.nodes) == 3
      assert length(graph.workflow.connections) == 2
    end

    test "compiles parallel workflow" do
      workflow = create_parallel_workflow()

      {:ok, %ExecutionGraph{} = graph} = WorkflowCompiler.compile(workflow)

      assert graph.total_nodes == 3

      # Webhook should have 2 outgoing connections
      webhook_node = Enum.find(workflow.nodes, &(&1.custom_id == "webhook"))
      connections = Map.get(graph.connection_map, {webhook_node.id, "success"}, [])
      assert length(connections) == 2
    end

    test "builds correct dependency graph" do
      workflow = create_simple_workflow()
      {:ok, graph} = WorkflowCompiler.compile(workflow)

      validate_node = Enum.find(workflow.nodes, &(&1.custom_id == "validate"))
      save_node = Enum.find(workflow.nodes, &(&1.custom_id == "save"))

      # validate depends on webhook, save depends on validate
      assert Map.has_key?(graph.dependency_graph, validate_node.id)
      assert Map.has_key?(graph.dependency_graph, save_node.id)
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
      webhook_node = Enum.find(workflow.nodes, &(&1.custom_id == "webhook"))
      {:ok, graph1} = WorkflowCompiler.compile(workflow, webhook_node.id)
      assert graph1.trigger_node.custom_id == "webhook"

      # Compile with schedule trigger
      schedule_node = Enum.find(workflow.nodes, &(&1.custom_id == "schedule"))
      {:ok, graph2} = WorkflowCompiler.compile(workflow, schedule_node.id)
      assert graph2.trigger_node.custom_id == "schedule"
    end

    test "returns error when node exists but is not a trigger" do
      workflow = create_simple_workflow()
      validate_node = Enum.find(workflow.nodes, &(&1.custom_id == "validate"))

      assert {:error, {:node_not_trigger, _, :action}} =
               WorkflowCompiler.compile(workflow, validate_node.id)
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
      assert length(workflow.connections) == 2

      {:ok, graph} = WorkflowCompiler.compile(workflow)

      # Compiled graph should only have reachable nodes (2 nodes)
      assert graph.total_nodes == 2
      assert length(graph.workflow.nodes) == 2
      assert length(graph.workflow.connections) == 1

      # Should only contain webhook and validate nodes
      node_custom_ids = Enum.map(graph.workflow.nodes, & &1.custom_id)
      assert "webhook" in node_custom_ids
      assert "validate" in node_custom_ids
      refute "orphan_a" in node_custom_ids
      refute "orphan_b" in node_custom_ids
    end

    test "keeps all nodes when everything is reachable" do
      workflow = create_simple_workflow()

      # All 3 nodes should be reachable from trigger
      assert length(workflow.nodes) == 3

      {:ok, graph} = WorkflowCompiler.compile(workflow)

      # All nodes should be preserved
      assert graph.total_nodes == 3
      assert length(graph.workflow.nodes) == 3
      assert length(graph.workflow.connections) == 2
    end
  end

  # ============================================================================
  # Ready Nodes Tests
  # ============================================================================

  describe "find_ready_nodes/4" do
    test "returns trigger node when nothing executed" do
      workflow = create_simple_workflow()
      {:ok, graph} = WorkflowCompiler.compile(workflow)

      ready = WorkflowCompiler.find_ready_nodes(graph, MapSet.new(), MapSet.new(), MapSet.new())

      assert length(ready) == 1
      assert hd(ready).custom_id == "webhook"
    end

    test "returns next nodes when dependencies satisfied" do
      workflow = create_simple_workflow()
      {:ok, graph} = WorkflowCompiler.compile(workflow)

      webhook_node = Enum.find(workflow.nodes, &(&1.custom_id == "webhook"))
      completed = MapSet.new([webhook_node.id])

      ready = WorkflowCompiler.find_ready_nodes(graph, completed, MapSet.new(), MapSet.new())

      assert length(ready) == 1
      assert hd(ready).custom_id == "validate"
    end

    test "returns parallel nodes when ready" do
      workflow = create_parallel_workflow()
      {:ok, graph} = WorkflowCompiler.compile(workflow)

      webhook_node = Enum.find(workflow.nodes, &(&1.custom_id == "webhook"))
      completed = MapSet.new([webhook_node.id])

      ready = WorkflowCompiler.find_ready_nodes(graph, completed, MapSet.new(), MapSet.new())

      assert length(ready) == 2
      ready_ids = Enum.map(ready, & &1.custom_id)
      assert "email" in ready_ids
      assert "log" in ready_ids
    end

    test "excludes failed and pending nodes" do
      workflow = create_parallel_workflow()
      {:ok, graph} = WorkflowCompiler.compile(workflow)

      webhook_node = Enum.find(workflow.nodes, &(&1.custom_id == "webhook"))
      email_node = Enum.find(workflow.nodes, &(&1.custom_id == "email"))

      completed = MapSet.new([webhook_node.id])
      failed = MapSet.new()
      pending = MapSet.new([email_node.id])

      ready = WorkflowCompiler.find_ready_nodes(graph, completed, failed, pending)

      # Only log should be ready (email is pending)
      assert length(ready) == 1
      assert hd(ready).custom_id == "log"
    end

    test "returns empty when all nodes processed" do
      workflow = create_simple_workflow()
      {:ok, graph} = WorkflowCompiler.compile(workflow)

      all_node_ids = Enum.map(workflow.nodes, & &1.id)
      completed = MapSet.new(all_node_ids)

      ready = WorkflowCompiler.find_ready_nodes(graph, completed, MapSet.new(), MapSet.new())

      assert length(ready) == 0
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
        assert Map.has_key?(graph.node_map, node.id)
        assert graph.node_map[node.id] == node
      end)
    end

    test "creates correct connection map" do
      workflow = create_parallel_workflow()
      {:ok, graph} = WorkflowCompiler.compile(workflow)

      webhook_node = Enum.find(workflow.nodes, &(&1.custom_id == "webhook"))

      # Webhook should have connections mapped by port
      assert Map.has_key?(graph.connection_map, {webhook_node.id, "success"})
      connections = graph.connection_map[{webhook_node.id, "success"}]
      assert length(connections) == 2
    end

    test "accurate total_nodes count" do
      workflow1 = create_simple_workflow()
      {:ok, graph1} = WorkflowCompiler.compile(workflow1)
      assert graph1.total_nodes == 3

      workflow2 = create_parallel_workflow()
      {:ok, graph2} = WorkflowCompiler.compile(workflow2)
      assert graph2.total_nodes == 3
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
      final_node = Enum.find(workflow.nodes, &(&1.custom_id == "final"))
      process_a_node = Enum.find(workflow.nodes, &(&1.custom_id == "process_a"))
      process_b_node = Enum.find(workflow.nodes, &(&1.custom_id == "process_b"))

      final_deps = Map.get(graph.dependency_graph, final_node.id, [])
      assert process_a_node.id in final_deps
      assert process_b_node.id in final_deps
      assert length(final_deps) == 2
    end

    test "waits for all dependencies in diamond pattern" do
      workflow = create_diamond_dependency_workflow()
      {:ok, graph} = WorkflowCompiler.compile(workflow)

      trigger_node = Enum.find(workflow.nodes, &(&1.custom_id == "trigger"))
      process_a_node = Enum.find(workflow.nodes, &(&1.custom_id == "process_a"))
      process_b_node = Enum.find(workflow.nodes, &(&1.custom_id == "process_b"))

      # Initially only trigger ready
      ready = WorkflowCompiler.find_ready_nodes(graph, MapSet.new(), MapSet.new(), MapSet.new())
      assert length(ready) == 1
      assert hd(ready).custom_id == "trigger"

      # After trigger completes, both process_a and process_b ready
      completed = MapSet.new([trigger_node.id])
      ready = WorkflowCompiler.find_ready_nodes(graph, completed, MapSet.new(), MapSet.new())
      assert length(ready) == 2
      ready_ids = Enum.map(ready, & &1.custom_id)
      assert "process_a" in ready_ids
      assert "process_b" in ready_ids

      # After only process_a completes, final should NOT be ready yet
      completed = MapSet.new([trigger_node.id, process_a_node.id])
      ready = WorkflowCompiler.find_ready_nodes(graph, completed, MapSet.new(), MapSet.new())
      ready_ids = Enum.map(ready, & &1.custom_id)
      refute "final" in ready_ids

      # After both process_a and process_b complete, final should be ready
      completed = MapSet.new([trigger_node.id, process_a_node.id, process_b_node.id])
      ready = WorkflowCompiler.find_ready_nodes(graph, completed, MapSet.new(), MapSet.new())
      assert length(ready) == 1
      assert hd(ready).custom_id == "final"
    end

    test "handles node with multiple dependencies correctly" do
      workflow = create_diamond_dependency_workflow()
      {:ok, graph} = WorkflowCompiler.compile(workflow)

      # Verify dependency graph structure
      trigger_node = Enum.find(workflow.nodes, &(&1.custom_id == "trigger"))
      process_a_node = Enum.find(workflow.nodes, &(&1.custom_id == "process_a"))
      process_b_node = Enum.find(workflow.nodes, &(&1.custom_id == "process_b"))
      final_node = Enum.find(workflow.nodes, &(&1.custom_id == "final"))

      # Process nodes should depend only on trigger
      assert graph.dependency_graph[process_a_node.id] == [trigger_node.id]
      assert graph.dependency_graph[process_b_node.id] == [trigger_node.id]

      # Final node should depend on both process nodes
      final_deps = graph.dependency_graph[final_node.id]
      assert length(final_deps) == 2
      assert process_a_node.id in final_deps
      assert process_b_node.id in final_deps
    end
  end

  # ============================================================================
  # Connection Map Edge Cases
  # ============================================================================

  describe "connection map edge cases" do
    test "handles nodes with multiple output ports" do
      workflow = create_multi_port_workflow()
      {:ok, graph} = WorkflowCompiler.compile(workflow)

      validate_node = Enum.find(workflow.nodes, &(&1.custom_id == "validate"))

      # Validate should have both success and error connections
      success_key = {validate_node.id, "success"}
      error_key = {validate_node.id, "error"}

      assert Map.has_key?(graph.connection_map, success_key)
      assert Map.has_key?(graph.connection_map, error_key)

      success_connections = graph.connection_map[success_key]
      error_connections = graph.connection_map[error_key]

      assert length(success_connections) == 1
      assert length(error_connections) == 1

      # Verify they point to correct targets
      save_node = Enum.find(workflow.nodes, &(&1.custom_id == "save"))
      error_log_node = Enum.find(workflow.nodes, &(&1.custom_id == "error_log"))

      assert hd(success_connections).to == save_node.id
      assert hd(error_connections).to == error_log_node.id
    end

    test "handles nodes with no outgoing connections" do
      workflow = create_terminal_node_workflow()
      {:ok, graph} = WorkflowCompiler.compile(workflow)

      output_node = Enum.find(workflow.nodes, &(&1.custom_id == "output"))

      # Output node should have no connections in the map
      success_key = {output_node.id, "success"}
      error_key = {output_node.id, "error"}

      refute Map.has_key?(graph.connection_map, success_key)
      refute Map.has_key?(graph.connection_map, error_key)

      # Should still be in node map though
      assert Map.has_key?(graph.node_map, output_node.id)
    end

    test "handles non-existent port lookups gracefully" do
      workflow = create_simple_workflow()
      {:ok, graph} = WorkflowCompiler.compile(workflow)

      webhook_node = Enum.find(workflow.nodes, &(&1.custom_id == "webhook"))

      # Non-existent ports should return empty lists
      invalid_key = {webhook_node.id, "invalid_port"}
      connections = Map.get(graph.connection_map, invalid_key, [])
      assert length(connections) == 0
    end

    test "groups connections correctly by source node and port" do
      workflow = create_parallel_workflow()
      {:ok, graph} = WorkflowCompiler.compile(workflow)

      webhook_node = Enum.find(workflow.nodes, &(&1.custom_id == "webhook"))
      email_node = Enum.find(workflow.nodes, &(&1.custom_id == "email"))
      log_node = Enum.find(workflow.nodes, &(&1.custom_id == "log"))

      # Webhook success port should have 2 connections
      success_key = {webhook_node.id, "success"}
      connections = graph.connection_map[success_key]
      assert length(connections) == 2

      # Verify target nodes
      target_ids = Enum.map(connections, & &1.to)
      assert email_node.id in target_ids
      assert log_node.id in target_ids

      # Each target should only appear once
      assert length(Enum.uniq(target_ids)) == 2
    end
  end
end
