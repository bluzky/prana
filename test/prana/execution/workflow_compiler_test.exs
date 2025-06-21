defmodule Prana.WorkflowCompilerTest do
  use ExUnit.Case, async: true

  alias Prana.{WorkflowCompiler, Workflow, Node, Connection, ExecutionGraph}

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
end