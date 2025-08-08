defmodule Prana.Core.WorkflowExecutionNodeSelectionTest do
  use ExUnit.Case, async: false

  alias Prana.{Connection, ExecutionGraph, IntegrationRegistry, Node, NodeExecution, TestSupport.TestIntegration, WorkflowExecution}

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

  describe "find_next_ready_node/1" do
    test "returns nil when no active nodes exist" do
      execution = create_basic_execution_with_empty_active_nodes()

      result = WorkflowExecution.find_next_ready_node(execution)

      assert result == nil
    end

    test "returns nil when active nodes have no satisfied dependencies" do
      # Create execution with active nodes that depend on uncompleted nodes
      execution = create_execution_with_unsatisfied_dependencies()

      result = WorkflowExecution.find_next_ready_node(execution)

      assert result == nil
    end

    test "returns single ready node when dependencies are satisfied" do
      # Create execution with one node ready to execute
      execution = create_execution_with_single_ready_node()

      result = WorkflowExecution.find_next_ready_node(execution)

      assert result != nil
      assert result.key == "ready_node"
    end

    test "selects node with highest execution_index when multiple nodes are ready" do
      # Create execution with multiple ready nodes with different execution indices
      execution = create_execution_with_multiple_ready_nodes()

      result = WorkflowExecution.find_next_ready_node(execution)

      assert result != nil
      # Should select node with highest execution_index (deepest in execution)
      assert result.key == "deep_node"
    end

    test "handles nodes with no input ports (trigger nodes)" do
      # Test nodes that don't require any input dependencies
      execution = create_execution_with_trigger_node()

      result = WorkflowExecution.find_next_ready_node(execution)

      assert result != nil
      assert result.key == "trigger_node"
    end

    test "filters out completed nodes from selection" do
      # Create execution where some active nodes are already completed
      execution = create_execution_with_completed_nodes()

      result = WorkflowExecution.find_next_ready_node(execution)

      # Should select the uncompleted ready node
      assert result != nil
      assert result.key == "uncompleted_node"
    end

    test "prioritizes nodes by execution_index in descending order" do
      # Test the sorting behavior explicitly
      execution = create_execution_with_sorted_nodes()

      result = WorkflowExecution.find_next_ready_node(execution)

      assert result != nil
      # Highest execution_index should be selected first
      assert result.key == "node_depth_5"
    end
  end

  # ============================================================================
  # Test Helpers
  # ============================================================================

  defp create_basic_execution_with_empty_active_nodes do
    execution_graph = %ExecutionGraph{
      workflow_id: "test_workflow",
      trigger_node_key: "trigger",
      dependency_graph: %{},
      connection_map: %{},
      reverse_connection_map: %{},
      node_map: %{},
      variables: %{}
    }

    %WorkflowExecution{
      id: "exec_1",
      workflow_id: "test_workflow",
      execution_graph: execution_graph,
      node_executions: %{},
      __runtime: %{
        "nodes" => %{},
        "env" => %{}
      },
      execution_data: %{
        "context_data" => %{
          "workflow" => %{},
          "node" => %{}
        },
        "active_paths" => %{},
        "active_nodes" => %{}  # Empty active nodes
      }
    }
  end

  defp create_execution_with_unsatisfied_dependencies do
    # Node B depends on Node A, but Node A is not completed
    node_a = Node.new("Node A", "test.simple_action", %{}, "node_a")
    node_b = Node.new("Node B", "test.simple_action", %{}, "node_b")

    connection = %Connection{
      from: "node_a",
      to: "node_b", 
      from_port: "success",
      to_port: "input"
    }

    execution_graph = %ExecutionGraph{
      workflow_id: "test_workflow",
      trigger_node_key: "node_a",
      dependency_graph: %{"node_b" => ["node_a"]},
      connection_map: %{{"node_a", "success"} => [connection]},
      reverse_connection_map: %{"node_b" => [connection]},
      node_map: %{"node_a" => node_a, "node_b" => node_b},
      variables: %{}
    }

    %WorkflowExecution{
      id: "exec_2",
      workflow_id: "test_workflow", 
      execution_graph: execution_graph,
      node_executions: %{},
      __runtime: %{
        "nodes" => %{},
        "env" => %{}
      },
      execution_data: %{
        "context_data" => %{
          "workflow" => %{},
          "node" => %{}
        },
        "active_paths" => %{},
        "active_nodes" => %{"node_b" => 1}  # Node B is active but depends on uncompleted node_a
      }
    }
  end

  defp create_execution_with_single_ready_node do
    ready_node = Node.new("Ready Node", "test.trigger_action", %{}, "ready_node")

    execution_graph = %ExecutionGraph{
      workflow_id: "test_workflow",
      trigger_node_key: "ready_node",
      dependency_graph: %{},
      connection_map: %{},
      reverse_connection_map: %{},
      node_map: %{"ready_node" => ready_node},
      variables: %{}
    }

    %WorkflowExecution{
      id: "exec_3",
      workflow_id: "test_workflow",
      execution_graph: execution_graph,
      node_executions: %{},
      __runtime: %{
        "nodes" => %{},
        "env" => %{}
      },
      execution_data: %{
        "context_data" => %{
          "workflow" => %{},
          "node" => %{}
        },
        "active_paths" => %{},
        "active_nodes" => %{"ready_node" => 1}
      }
    }
  end

  defp create_execution_with_multiple_ready_nodes do
    shallow_node = Node.new("Shallow Node", "test.trigger_action", %{}, "shallow_node")
    deep_node = Node.new("Deep Node", "test.trigger_action", %{}, "deep_node")

    execution_graph = %ExecutionGraph{
      workflow_id: "test_workflow",
      trigger_node_key: "shallow_node",
      dependency_graph: %{},
      connection_map: %{},
      reverse_connection_map: %{},
      node_map: %{"shallow_node" => shallow_node, "deep_node" => deep_node},
      variables: %{}
    }

    %WorkflowExecution{
      id: "exec_4",
      workflow_id: "test_workflow",
      execution_graph: execution_graph,
      node_executions: %{},
      __runtime: %{
        "nodes" => %{},
        "env" => %{}
      },
      execution_data: %{
        "context_data" => %{
          "workflow" => %{},
          "node" => %{}
        },
        "active_paths" => %{},
        "active_nodes" => %{
          "shallow_node" => 1,  # Lower execution_index
          "deep_node" => 3      # Higher execution_index - should be selected
        }
      }
    }
  end

  defp create_execution_with_trigger_node do
    trigger_node = Node.new("Trigger Node", "test.trigger_action", %{}, "trigger_node")

    execution_graph = %ExecutionGraph{
      workflow_id: "test_workflow",
      trigger_node_key: "trigger_node",
      dependency_graph: %{},
      connection_map: %{},
      reverse_connection_map: %{},
      node_map: %{"trigger_node" => trigger_node},
      variables: %{}
    }

    %WorkflowExecution{
      id: "exec_5",
      workflow_id: "test_workflow",
      execution_graph: execution_graph,
      node_executions: %{},
      __runtime: %{
        "nodes" => %{},
        "env" => %{}
      },
      execution_data: %{
        "context_data" => %{
          "workflow" => %{},
          "node" => %{}
        },
        "active_paths" => %{},
        "active_nodes" => %{"trigger_node" => 1}
      }
    }
  end

  defp create_execution_with_completed_nodes do
    completed_node = Node.new("Completed Node", "test.simple_action", %{}, "completed_node")
    uncompleted_node = Node.new("Uncompleted Node", "test.trigger_action", %{}, "uncompleted_node")

    execution_graph = %ExecutionGraph{
      workflow_id: "test_workflow",
      trigger_node_key: "completed_node",
      dependency_graph: %{},
      connection_map: %{},
      reverse_connection_map: %{},
      node_map: %{
        "completed_node" => completed_node,
        "uncompleted_node" => uncompleted_node
      },
      variables: %{}
    }

    # Create completed execution for completed_node
    completed_execution = %NodeExecution{
      node_key: "completed_node",
      status: "completed",
      params: %{},
      output_data: %{"result" => "success"},
      output_port: "success",
      started_at: DateTime.utc_now(),
      completed_at: DateTime.utc_now()
    }

    %WorkflowExecution{
      id: "exec_6",
      workflow_id: "test_workflow",
      execution_graph: execution_graph,
      node_executions: %{"completed_node" => [completed_execution]},
      __runtime: %{
        "nodes" => %{"completed_node" => %{"result" => "success"}},
        "env" => %{}
      },
      execution_data: %{
        "context_data" => %{
          "workflow" => %{},
          "node" => %{}
        },
        "active_paths" => %{},
        "active_nodes" => %{
          "completed_node" => 1,    # This is completed, shouldn't be selected
          "uncompleted_node" => 2   # This should be selected
        }
      }
    }
  end

  defp create_execution_with_sorted_nodes do
    # Create multiple nodes with different execution indices to test sorting
    nodes = for i <- 1..5 do
      key = "node_depth_#{i}"
      {key, Node.new("Node #{i}", "test.trigger_action", %{}, key)}
    end

    node_map = Map.new(nodes)
    active_nodes = Map.new(nodes, fn {key, _node} ->
      # Extract number from key for execution_index
      parts = String.split(key, "_")
      num_str = List.last(parts)
      execution_index = String.to_integer(num_str)
      {key, execution_index}
    end)

    execution_graph = %ExecutionGraph{
      workflow_id: "test_workflow",
      trigger_node_key: "node_depth_1",
      dependency_graph: %{},
      connection_map: %{},
      reverse_connection_map: %{},
      node_map: node_map,
      variables: %{}
    }

    %WorkflowExecution{
      id: "exec_7",
      workflow_id: "test_workflow",
      execution_graph: execution_graph,
      node_executions: %{},
      __runtime: %{
        "nodes" => %{},
        "env" => %{}
      },
      execution_data: %{
        "context_data" => %{
          "workflow" => %{},
          "node" => %{}
        },
        "active_paths" => %{},
        "active_nodes" => active_nodes  # Should select node_depth_5 (highest execution_index)
      }
    }
  end
end