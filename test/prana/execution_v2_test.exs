defmodule Prana.Execution.V2Test do
  use ExUnit.Case
  
  alias Prana.Execution.V2, as: Execution
  alias Prana.ExecutionGraph
  alias Prana.Node
  alias Prana.NodeExecution
  
  doctest Prana.Execution.V2
  
  describe "new/2" do
    test "creates execution with embedded ExecutionGraph" do
      execution_graph = create_test_execution_graph()
      context = %{
        variables: %{api_key: "test123"},
        environment: %{env: "test"},
        metadata: %{user_id: 456}
      }
      
      execution = Execution.new(execution_graph, context)
      
      assert execution.execution_graph == execution_graph
      assert execution.status == :pending
      assert execution.variables == %{api_key: "test123"}
      assert execution.environment == %{env: "test"}
      assert execution.metadata == %{user_id: 456}
      assert execution.active_nodes == MapSet.new(["trigger"])
      assert execution.node_depth == %{"trigger" => 0}
    end
    
    test "creates execution with default context" do
      execution_graph = create_test_execution_graph()
      
      execution = Execution.new(execution_graph)
      
      assert execution.execution_graph == execution_graph
      assert execution.variables == %{}
      assert execution.environment == %{}
      assert execution.metadata == %{}
    end
  end
  
  describe "start/1" do
    test "marks execution as started with timestamp" do
      execution = create_test_execution()
      
      started_execution = Execution.start(execution)
      
      assert started_execution.status == :running
      assert started_execution.started_at != nil
    end
  end
  
  describe "complete/2" do
    test "marks execution as completed with output data" do
      execution = create_test_execution()
      output_data = %{result: "success"}
      
      completed_execution = Execution.complete(execution, output_data)
      
      assert completed_execution.status == :completed
      assert completed_execution.completed_at != nil
      assert completed_execution.metadata["output_data"] == output_data
    end
    
    test "completes execution without output data" do
      execution = create_test_execution()
      
      completed_execution = Execution.complete(execution)
      
      assert completed_execution.status == :completed
      assert completed_execution.metadata["output_data"] == %{}
    end
  end
  
  describe "fail/2" do
    test "marks execution as failed with error data" do
      execution = create_test_execution()
      error_data = %{error: "network timeout", code: 500}
      
      failed_execution = Execution.fail(execution, error_data)
      
      assert failed_execution.status == :failed
      assert failed_execution.completed_at != nil
      assert failed_execution.metadata["error_data"] == error_data
    end
  end
  
  describe "suspend/4" do
    test "suspends execution with consolidated suspension data" do
      execution = create_test_execution()
      suspension_data = %{wait_till: DateTime.add(DateTime.utc_now(), 3600, :second)}
      
      suspended_execution = Execution.suspend(execution, "webhook_node", :webhook, suspension_data)
      
      assert suspended_execution.status == :suspended
      assert suspended_execution.suspension.node_id == "webhook_node"
      assert suspended_execution.suspension.type == :webhook
      assert suspended_execution.suspension.data == suspension_data
      assert suspended_execution.suspension.suspended_at != nil
    end
  end
  
  describe "resume_suspension/1" do
    test "clears suspension state" do
      execution = create_test_execution()
      suspension_data = %{wait_till: DateTime.add(DateTime.utc_now(), 3600, :second)}
      suspended_execution = Execution.suspend(execution, "webhook_node", :webhook, suspension_data)
      
      resumed_execution = Execution.resume_suspension(suspended_execution)
      
      assert resumed_execution.suspension == nil
    end
  end
  
  describe "get_ready_nodes/1" do
    test "returns ready nodes based on dependencies" do
      execution = create_test_execution_with_completed_nodes()
      
      ready_nodes = Execution.get_ready_nodes(execution)
      
      # Should return nodes that have their dependencies satisfied
      assert length(ready_nodes) > 0
      assert Enum.all?(ready_nodes, &(&1.__struct__ == Node))
    end
  end
  
  describe "terminal?/1" do
    test "returns true for completed execution" do
      execution = create_test_execution() |> Execution.complete()
      assert Execution.terminal?(execution) == true
    end
    
    test "returns true for failed execution" do
      execution = create_test_execution() |> Execution.fail(%{error: "test"})
      assert Execution.terminal?(execution) == true
    end
    
    test "returns false for running execution" do
      execution = create_test_execution() |> Execution.start()
      assert Execution.terminal?(execution) == false
    end
  end
  
  describe "running?/1" do
    test "returns true for pending execution" do
      execution = create_test_execution()
      assert Execution.running?(execution) == true
    end
    
    test "returns true for running execution" do
      execution = create_test_execution() |> Execution.start()
      assert Execution.running?(execution) == true
    end
    
    test "returns true for suspended execution" do
      execution = create_test_execution() 
                  |> Execution.suspend("node", :webhook, %{})
      assert Execution.running?(execution) == true
    end
    
    test "returns false for completed execution" do
      execution = create_test_execution() |> Execution.complete()
      assert Execution.running?(execution) == false
    end
  end
  
  describe "suspended?/1" do
    test "returns true for suspended execution" do
      execution = create_test_execution() 
                  |> Execution.suspend("node", :webhook, %{})
      assert Execution.suspended?(execution) == true
    end
    
    test "returns false for non-suspended execution" do
      execution = create_test_execution()
      assert Execution.suspended?(execution) == false
    end
  end
  
  describe "get_suspension_info/1" do
    test "returns suspension info for suspended execution" do
      execution = create_test_execution()
      suspension_data = %{wait_till: DateTime.add(DateTime.utc_now(), 3600, :second)}
      suspended_execution = Execution.suspend(execution, "webhook_node", :webhook, suspension_data)
      
      {:ok, suspension_info} = Execution.get_suspension_info(suspended_execution)
      
      assert suspension_info.node_id == "webhook_node"
      assert suspension_info.type == :webhook
      assert suspension_info.data == suspension_data
    end
    
    test "returns :not_suspended for non-suspended execution" do
      execution = create_test_execution()
      
      result = Execution.get_suspension_info(execution)
      
      assert result == :not_suspended
    end
  end
  
  describe "to_storage_format/1 and from_storage_format/2" do
    test "converts execution to storage format and back" do
      execution = create_test_execution()
      
      # Convert to storage format (excludes execution_graph)
      stored_data = Execution.to_storage_format(execution)
      
      assert Map.has_key?(stored_data, :id)
      assert Map.has_key?(stored_data, :status)
      refute Map.has_key?(stored_data, :execution_graph)
      
      # Convert back from storage format
      restored_execution = Execution.from_storage_format(stored_data, execution.execution_graph)
      
      assert restored_execution.id == execution.id
      assert restored_execution.status == execution.status
      assert restored_execution.execution_graph == execution.execution_graph
    end
  end
  
  # Helper functions
  
  defp create_test_execution_graph do
    nodes = %{
      "trigger" => %Node{key: "trigger", integration_name: "manual", action_name: "trigger"},
      "action" => %Node{key: "action", integration_name: "manual", action_name: "action"}
    }
    
    ExecutionGraph.new(
      "test_workflow",
      1,
      "trigger",
      nodes,
      %{},  # connection_map
      %{},  # reverse_connection_map
      %{}   # dependency_graph
    )
  end
  
  defp create_test_execution do
    execution_graph = create_test_execution_graph()
    Execution.new(execution_graph)
  end
  
  defp create_test_execution_with_completed_nodes do
    execution = create_test_execution()
    
    # Add some completed nodes to the execution
    %{execution | 
      completed_nodes: %{"trigger" => %{result: "success"}},
      active_nodes: MapSet.new(["action"])
    }
  end
end