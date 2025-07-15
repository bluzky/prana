defmodule Prana.ExecutionGraphTest do
  use ExUnit.Case
  
  alias Prana.ExecutionGraph
  alias Prana.Node
  alias Prana.Connection
  
  doctest Prana.ExecutionGraph
  
  describe "new/7" do
    test "creates ExecutionGraph with all required fields" do
      nodes = %{
        "trigger" => %Node{key: "trigger", integration_name: "manual", action_name: "trigger"},
        "action" => %Node{key: "action", integration_name: "manual", action_name: "action"}
      }
      
      connection_map = %{
        {"trigger", "success"} => [
          %Connection{from: "trigger", from_port: "success", to: "action", to_port: "input"}
        ]
      }
      
      reverse_connection_map = %{
        "action" => [
          %Connection{from: "trigger", from_port: "success", to: "action", to_port: "input"}
        ]
      }
      
      dependency_graph = %{"action" => ["trigger"]}
      
      graph = ExecutionGraph.new(
        "wf_123",
        1,
        "trigger",
        nodes,
        connection_map,
        reverse_connection_map,
        dependency_graph
      )
      
      assert graph.workflow_id == "wf_123"
      assert graph.workflow_version == 1
      assert graph.trigger_node_key == "trigger"
      assert graph.nodes == nodes
      assert graph.connection_map == connection_map
      assert graph.reverse_connection_map == reverse_connection_map
      assert graph.dependency_graph == dependency_graph
    end
  end
  
  describe "get_trigger_node/1" do
    test "returns the trigger node" do
      trigger_node = %Node{key: "trigger", integration_name: "manual", action_name: "trigger"}
      nodes = %{"trigger" => trigger_node}
      
      graph = ExecutionGraph.new("wf_123", 1, "trigger", nodes, %{}, %{}, %{})
      
      assert ExecutionGraph.get_trigger_node(graph) == trigger_node
    end
    
    test "returns nil if trigger node not found" do
      graph = ExecutionGraph.new("wf_123", 1, "missing", %{}, %{}, %{}, %{})
      
      assert ExecutionGraph.get_trigger_node(graph) == nil
    end
  end
  
  describe "get_node/2" do
    test "returns node by key" do
      action_node = %Node{key: "action", integration_name: "manual", action_name: "action"}
      nodes = %{"action" => action_node}
      
      graph = ExecutionGraph.new("wf_123", 1, "trigger", nodes, %{}, %{}, %{})
      
      assert ExecutionGraph.get_node(graph, "action") == action_node
    end
    
    test "returns nil for non-existent node" do
      graph = ExecutionGraph.new("wf_123", 1, "trigger", %{}, %{}, %{}, %{})
      
      assert ExecutionGraph.get_node(graph, "missing") == nil
    end
  end
  
  describe "get_outgoing_connections/3" do
    test "returns connections for node and output port" do
      connection = %Connection{from: "trigger", from_port: "success", to: "action", to_port: "input"}
      connection_map = %{{"trigger", "success"} => [connection]}
      
      graph = ExecutionGraph.new("wf_123", 1, "trigger", %{}, connection_map, %{}, %{})
      
      assert ExecutionGraph.get_outgoing_connections(graph, "trigger", "success") == [connection]
    end
    
    test "returns empty list for non-existent connection" do
      graph = ExecutionGraph.new("wf_123", 1, "trigger", %{}, %{}, %{}, %{})
      
      assert ExecutionGraph.get_outgoing_connections(graph, "trigger", "success") == []
    end
  end
  
  describe "get_incoming_connections/2" do
    test "returns incoming connections for node" do
      connection = %Connection{from: "trigger", from_port: "success", to: "action", to_port: "input"}
      reverse_connection_map = %{"action" => [connection]}
      
      graph = ExecutionGraph.new("wf_123", 1, "trigger", %{}, %{}, reverse_connection_map, %{})
      
      assert ExecutionGraph.get_incoming_connections(graph, "action") == [connection]
    end
    
    test "returns empty list for node with no incoming connections" do
      graph = ExecutionGraph.new("wf_123", 1, "trigger", %{}, %{}, %{}, %{})
      
      assert ExecutionGraph.get_incoming_connections(graph, "action") == []
    end
  end
  
  describe "get_node_dependencies/2" do
    test "returns node dependencies" do
      dependency_graph = %{"action" => ["trigger"], "final" => ["action"]}
      
      graph = ExecutionGraph.new("wf_123", 1, "trigger", %{}, %{}, %{}, dependency_graph)
      
      assert ExecutionGraph.get_node_dependencies(graph, "action") == ["trigger"]
      assert ExecutionGraph.get_node_dependencies(graph, "final") == ["action"]
    end
    
    test "returns empty list for node with no dependencies" do
      graph = ExecutionGraph.new("wf_123", 1, "trigger", %{}, %{}, %{}, %{})
      
      assert ExecutionGraph.get_node_dependencies(graph, "trigger") == []
    end
  end
  
  describe "node_count/1" do
    test "returns total number of nodes" do
      nodes = %{
        "trigger" => %Node{key: "trigger"},
        "action1" => %Node{key: "action1"},
        "action2" => %Node{key: "action2"}
      }
      
      graph = ExecutionGraph.new("wf_123", 1, "trigger", nodes, %{}, %{}, %{})
      
      assert ExecutionGraph.node_count(graph) == 3
    end
    
    test "returns 0 for empty graph" do
      graph = ExecutionGraph.new("wf_123", 1, "trigger", %{}, %{}, %{}, %{})
      
      assert ExecutionGraph.node_count(graph) == 0
    end
  end
end