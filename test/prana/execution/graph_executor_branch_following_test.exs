defmodule Prana.GraphExecutorBranchFollowingTest do
  @moduledoc """
  Tests to verify that GraphExecutor follows branches to completion rather than executing in batches.
  
  The key behavioral change is:
  - OLD: Find all ready nodes → execute all in batch → route all outputs → repeat
  - NEW: Find ready nodes → select one node → execute it → route its output → repeat
  
  This ensures that branches are followed to completion before switching to other branches.
  """
  
  # Cannot be async due to named GenServer
  use ExUnit.Case, async: false
  
  alias Prana.Connection
  alias Prana.ExecutionGraph
  alias Prana.GraphExecutor
  alias Prana.IntegrationRegistry
  alias Prana.Node
  alias Prana.TestSupport.TestIntegration
  alias Prana.Workflow
  alias Prana.WorkflowCompiler
  alias Prana.WorkflowSettings
  
  describe "branch following execution" do
    setup do
      # Start the IntegrationRegistry GenServer for testing
      start_supervised!(Prana.IntegrationRegistry)
      
      # Register test integration
      :ok = IntegrationRegistry.register_integration(TestIntegration)
      
      :ok
    end
    
    test "follows single branch to completion before switching branches" do
      # Create a diamond pattern: trigger → (branch_a, branch_b) → merge
      # With branch-following, one branch should complete fully before the other starts
      
      trigger_node = %Node{
        id: "trigger", 
        custom_id: "trigger",
        name: "Trigger",
        type: :trigger,
        integration_name: "test",
        action_name: "simple_action",
        input_map: %{},
        output_ports: ["success"],
        input_ports: []
      }
      
      # Branch A: two sequential nodes
      branch_a1 = %Node{
        id: "branch_a1",
        custom_id: "branch_a1", 
        name: "Branch A Step 1",
        type: :action,
        integration_name: "test",
        action_name: "simple_action",
        input_map: %{},
        output_ports: ["success"],
        input_ports: ["input"]
      }
      
      branch_a2 = %Node{
        id: "branch_a2",
        custom_id: "branch_a2",
        name: "Branch A Step 2", 
        type: :action,
        integration_name: "test",
        action_name: "simple_action",
        input_map: %{},
        output_ports: ["success"],
        input_ports: ["input"]
      }
      
      # Branch B: two sequential nodes
      branch_b1 = %Node{
        id: "branch_b1",
        custom_id: "branch_b1",
        name: "Branch B Step 1",
        type: :action, 
        integration_name: "test",
        action_name: "simple_action",
        input_map: %{},
        output_ports: ["success"],
        input_ports: ["input"]
      }
      
      branch_b2 = %Node{
        id: "branch_b2",
        custom_id: "branch_b2",
        name: "Branch B Step 2",
        type: :action,
        integration_name: "test", 
        action_name: "simple_action",
        input_map: %{},
        output_ports: ["success"],
        input_ports: ["input"]
      }
      
      # Merge node (waits for both branches)
      merge_node = %Node{
        id: "merge",
        custom_id: "merge",
        name: "Merge",
        type: :action,
        integration_name: "test",
        action_name: "simple_action", 
        input_map: %{},
        output_ports: ["success"],
        input_ports: ["input_a", "input_b"]
      }
      
      connections = [
        # Trigger to both branch starts
        %Connection{
          id: "trigger_to_a1",
          from_node_id: "trigger",
          from_port: "success",
          to_node_id: "branch_a1",
          to_port: "input",
          data_mapping: %{}
        },
        %Connection{
          id: "trigger_to_b1", 
          from_node_id: "trigger",
          from_port: "success",
          to_node_id: "branch_b1",
          to_port: "input",
          data_mapping: %{}
        },
        
        # Branch A sequence
        %Connection{
          id: "a1_to_a2",
          from_node_id: "branch_a1",
          from_port: "success",
          to_node_id: "branch_a2", 
          to_port: "input",
          data_mapping: %{}
        },
        
        # Branch B sequence  
        %Connection{
          id: "b1_to_b2",
          from_node_id: "branch_b1",
          from_port: "success",
          to_node_id: "branch_b2",
          to_port: "input",
          data_mapping: %{}
        },
        
        # Both branches to merge
        %Connection{
          id: "a2_to_merge",
          from_node_id: "branch_a2", 
          from_port: "success",
          to_node_id: "merge",
          to_port: "input_a",
          data_mapping: %{}
        },
        %Connection{
          id: "b2_to_merge",
          from_node_id: "branch_b2",
          from_port: "success", 
          to_node_id: "merge",
          to_port: "input_b",
          data_mapping: %{}
        }
      ]
      
      workflow = %Workflow{
        id: "branch_following_test",
        name: "Branch Following Test",
        nodes: [trigger_node, branch_a1, branch_a2, branch_b1, branch_b2, merge_node],
        connections: connections,
        variables: %{},
        settings: %WorkflowSettings{},
        metadata: %{}
      }
      
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "trigger")
      
      input_data = %{"test" => "data"}
      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{},
        metadata: %{}
      }
      
      # Execute workflow
      {:ok, execution} = GraphExecutor.execute_graph(execution_graph, input_data, context)
      
      # Verify execution completed successfully
      assert execution.status == :completed
      assert length(execution.node_executions) == 6
      
      # Analyze execution order to verify branch following
      execution_order = Enum.map(execution.node_executions, & &1.node_id)
      
      # The trigger should be first
      assert List.first(execution_order) == "trigger"
      
      # After trigger, one branch should complete before the other starts
      # Due to branch-following, we should see patterns like:
      # trigger → branch_a1 → branch_a2 → branch_b1 → branch_b2 → merge
      # OR
      # trigger → branch_b1 → branch_b2 → branch_a1 → branch_a2 → merge
      
      trigger_index = Enum.find_index(execution_order, &(&1 == "trigger"))
      a1_index = Enum.find_index(execution_order, &(&1 == "branch_a1"))
      a2_index = Enum.find_index(execution_order, &(&1 == "branch_a2"))
      b1_index = Enum.find_index(execution_order, &(&1 == "branch_b1"))
      b2_index = Enum.find_index(execution_order, &(&1 == "branch_b2"))
      merge_index = Enum.find_index(execution_order, &(&1 == "merge"))
      
      # Trigger should be first
      assert trigger_index == 0
      
      # Branch sequences should be maintained (a1 before a2, b1 before b2)
      assert a1_index < a2_index, "Branch A sequence not maintained: a1=#{a1_index}, a2=#{a2_index}"
      assert b1_index < b2_index, "Branch B sequence not maintained: b1=#{b1_index}, b2=#{b2_index}"
      
      # Merge should be last (after both branches complete)
      assert merge_index == 5
      
      # With branch following, one complete branch should execute before the other starts
      # This means either:
      # 1. a1, a2 both come before b1, b2 
      # 2. b1, b2 both come before a1, a2
      branch_a_complete_before_b_starts = a2_index < b1_index
      branch_b_complete_before_a_starts = b2_index < a1_index
      
      # One of these should be true (branch following behavior)
      branch_following_detected = branch_a_complete_before_b_starts || branch_b_complete_before_a_starts
      
      assert branch_following_detected, 
        "Branch following not detected. Execution order: #{inspect(execution_order)}. " <>
        "Expected one branch to complete before other starts, but got interleaved execution."
      
      IO.puts("✓ Branch following detected. Execution order: #{inspect(execution_order)}")
    end
    
    test "select_node_for_branch_following prioritizes continuing active branches" do
      # Test the node selection logic directly
      
      # Create nodes
      start_node = %Node{id: "start", custom_id: "start"}
      continuing_node = %Node{id: "continuing", custom_id: "continuing"}  
      new_branch_node = %Node{id: "new_branch", custom_id: "new_branch"}
      
      # Create mock execution graph with connections
      connections = [
        %Connection{
          id: "start_to_continuing",
          from_node_id: "start", 
          from_port: "success",
          to_node_id: "continuing",
          to_port: "input",
          data_mapping: %{}
        }
      ]
      
      execution_graph = %ExecutionGraph{
        workflow: %Workflow{connections: connections},
        dependency_graph: %{
          "continuing" => ["start"],
          "new_branch" => []
        },
        connection_map: %{},
        reverse_connection_map: %{
          "continuing" => [hd(connections)]
        },
        node_map: %{},
        trigger_node: start_node,
        total_nodes: 3
      }
      
      # Context with active path from start node
      execution_context = %{
        "active_paths" => %{"start_success" => true}
      }
      
      ready_nodes = [continuing_node, new_branch_node]
      
      # Should select the continuing node over the new branch
      selected = GraphExecutor.select_node_for_branch_following(ready_nodes, execution_graph, execution_context)
      
      assert selected.id == "continuing", 
        "Expected to select continuing node, but got #{selected.id}"
    end
    
    test "select_node_for_branch_following falls back to dependency-based selection" do
      # Test when no active branches exist
      
      node_with_deps = %Node{id: "with_deps", custom_id: "with_deps"}
      node_no_deps = %Node{id: "no_deps", custom_id: "no_deps"}
      
      execution_graph = %ExecutionGraph{
        workflow: %Workflow{connections: []},
        dependency_graph: %{
          "with_deps" => ["some_other_node"],
          "no_deps" => []
        },
        connection_map: %{},
        reverse_connection_map: %{},
        node_map: %{},
        trigger_node: node_no_deps,
        total_nodes: 2
      }
      
      # No active paths
      execution_context = %{"active_paths" => %{}}
      
      ready_nodes = [node_with_deps, node_no_deps]
      
      # Should prefer node with fewer dependencies
      selected = GraphExecutor.select_node_for_branch_following(ready_nodes, execution_graph, execution_context)
      
      assert selected.id == "no_deps",
        "Expected to select node with fewer dependencies, but got #{selected.id}"
    end
  end
end