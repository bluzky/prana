defmodule Prana.ExecutionGraph.MigrationTest do
  use ExUnit.Case
  
  alias Prana.ExecutionGraph
  alias Prana.ExecutionGraph.Migration
  alias Prana.Execution
  alias Prana.Execution.V2, as: ExecutionV2
  alias Prana.Node
  alias Prana.Workflow
  alias Prana.Connection
  
  doctest Prana.ExecutionGraph.Migration
  
  describe "from_legacy/1" do
    test "converts legacy ExecutionGraph to new format" do
      # Create legacy ExecutionGraph structure
      trigger_node = %Node{key: "trigger", integration_name: "manual", action_name: "trigger"}
      action_node = %Node{key: "action", integration_name: "manual", action_name: "action"}
      
      workflow = %Workflow{
        id: "wf_123",
        version: 2,
        nodes: [trigger_node, action_node],
        connections: %{
          "trigger" => %{
            "success" => [
              %Connection{from: "trigger", from_port: "success", to: "action", to_port: "input"}
            ]
          }
        }
      }
      
      legacy_graph = %{
        workflow: workflow,
        trigger_node: trigger_node,
        node_map: %{
          "trigger" => trigger_node,
          "action" => action_node
        },
        connection_map: %{
          {"trigger", "success"} => [
            %Connection{from: "trigger", from_port: "success", to: "action", to_port: "input"}
          ]
        },
        reverse_connection_map: %{
          "action" => [
            %Connection{from: "trigger", from_port: "success", to: "action", to_port: "input"}
          ]
        },
        dependency_graph: %{"action" => ["trigger"]}
      }
      
      # Convert to new format
      new_graph = Migration.from_legacy(legacy_graph)
      
      # Verify conversion
      assert new_graph.workflow_id == "wf_123"
      assert new_graph.workflow_version == 2
      assert new_graph.trigger_node_key == "trigger"
      assert new_graph.nodes == legacy_graph.node_map
      assert new_graph.connection_map == legacy_graph.connection_map
      assert new_graph.reverse_connection_map == legacy_graph.reverse_connection_map
      assert new_graph.dependency_graph == legacy_graph.dependency_graph
    end
    
    test "handles legacy graph without node_map by building it from workflow" do
      trigger_node = %Node{key: "trigger", integration_name: "manual", action_name: "trigger"}
      
      workflow = %Workflow{
        id: "wf_123",
        nodes: [trigger_node]
      }
      
      legacy_graph = %{
        workflow: workflow,
        trigger_node: trigger_node,
        connection_map: %{},
        reverse_connection_map: %{},
        dependency_graph: %{}
      }
      
      new_graph = Migration.from_legacy(legacy_graph)
      
      assert new_graph.nodes == %{"trigger" => trigger_node}
    end
  end
  
  describe "to_legacy/1" do
    test "converts new ExecutionGraph back to legacy format" do
      # Create new ExecutionGraph
      trigger_node = %Node{key: "trigger", integration_name: "manual", action_name: "trigger"}
      action_node = %Node{key: "action", integration_name: "manual", action_name: "action"}
      
      nodes = %{
        "trigger" => trigger_node,
        "action" => action_node
      }
      
      connection = %Connection{from: "trigger", from_port: "success", to: "action", to_port: "input"}
      connection_map = %{{"trigger", "success"} => [connection]}
      reverse_connection_map = %{"action" => [connection]}
      dependency_graph = %{"action" => ["trigger"]}
      
      new_graph = ExecutionGraph.new(
        "wf_123",
        1,
        "trigger",
        nodes,
        connection_map,
        reverse_connection_map,
        dependency_graph
      )
      
      # Convert to legacy format
      legacy_graph = Migration.to_legacy(new_graph)
      
      # Verify conversion
      assert legacy_graph.workflow.id == "wf_123"
      assert legacy_graph.workflow.version == 1
      assert legacy_graph.trigger_node == trigger_node
      assert legacy_graph.node_map == nodes
      assert legacy_graph.connection_map == connection_map
      assert legacy_graph.reverse_connection_map == reverse_connection_map
      assert legacy_graph.dependency_graph == dependency_graph
      assert legacy_graph.total_nodes == 2
    end
  end
  
  describe "to_legacy_execution_format/1" do
    test "converts execution with embedded ExecutionGraph to legacy format" do
      # Create execution with embedded ExecutionGraph
      execution_graph = create_test_execution_graph()
      execution = ExecutionV2.new(execution_graph, %{variables: %{test: "value"}})
      
      # Convert to legacy format
      {legacy_execution, legacy_execution_graph} = Migration.to_legacy_execution_format(execution)
      
      # Verify execution conversion
      assert legacy_execution.id == execution.id
      assert legacy_execution.variables == execution.variables
      refute Map.has_key?(legacy_execution, :execution_graph)
      
      # Verify execution graph conversion
      assert legacy_execution_graph.workflow.id == execution_graph.workflow_id
      assert legacy_execution_graph.trigger_node.key == execution_graph.trigger_node_key
    end
  end
  
  describe "from_legacy_execution_format/2" do
    test "creates execution with embedded ExecutionGraph from legacy format" do
      # Create legacy structures
      trigger_node = %Node{key: "trigger", integration_name: "manual", action_name: "trigger"}
      
      legacy_execution = %Execution{
        id: "exec_123",
        workflow_id: "wf_123",
        vars: %{test: "value"}
      }
      
      legacy_execution_graph = %{
        workflow: %Workflow{id: "wf_123", nodes: [trigger_node]},
        trigger_node: trigger_node,
        node_map: %{"trigger" => trigger_node},
        connection_map: %{},
        reverse_connection_map: %{},
        dependency_graph: %{}
      }
      
      # Convert to new format
      new_execution = Migration.from_legacy_execution_format(legacy_execution, legacy_execution_graph)
      
      # Verify conversion
      assert new_execution.id == "exec_123"
      assert new_execution.vars == %{test: "value"}
      assert new_execution.execution_graph.workflow_id == "wf_123"
      assert new_execution.execution_graph.trigger_node_key == "trigger"
    end
  end
  
  describe "round-trip conversion" do
    test "legacy -> new -> legacy preserves data integrity" do
      # Create original legacy structure
      trigger_node = %Node{key: "trigger", integration_name: "manual", action_name: "trigger"}
      action_node = %Node{key: "action", integration_name: "manual", action_name: "action"}
      
      original_workflow = %Workflow{
        id: "wf_123",
        version: 1,
        nodes: [trigger_node, action_node]
      }
      
      original_legacy_graph = %{
        workflow: original_workflow,
        trigger_node: trigger_node,
        node_map: %{"trigger" => trigger_node, "action" => action_node},
        connection_map: %{},
        reverse_connection_map: %{},
        dependency_graph: %{"action" => ["trigger"]}
      }
      
      # Convert: legacy -> new -> legacy
      new_graph = Migration.from_legacy(original_legacy_graph)
      round_trip_legacy_graph = Migration.to_legacy(new_graph)
      
      # Verify key fields are preserved
      assert round_trip_legacy_graph.workflow.id == original_legacy_graph.workflow.id
      assert round_trip_legacy_graph.trigger_node.key == original_legacy_graph.trigger_node.key
      assert round_trip_legacy_graph.node_map == original_legacy_graph.node_map
      assert round_trip_legacy_graph.dependency_graph == original_legacy_graph.dependency_graph
    end
  end
  
  # Helper functions
  
  defp create_test_execution_graph do
    trigger_node = %Node{key: "trigger", integration_name: "manual", action_name: "trigger"}
    
    ExecutionGraph.new(
      "test_workflow",
      1,
      "trigger",
      %{"trigger" => trigger_node},
      %{},  # connection_map
      %{},  # reverse_connection_map
      %{}   # dependency_graph
    )
  end
end