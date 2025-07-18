defmodule Prana.Core.ExecutionStructTest do
  use ExUnit.Case, async: true

  alias Prana.{WorkflowExecution, NodeExecution}
  alias Prana.{ExecutionGraph, Node}

  describe "WorkflowExecution.from_map/1" do
    test "restores workflow execution from map with string keys" do
      execution_map = %{
        "id" => "exec_123",
        "workflow_id" => "wf_456",
        "workflow_version" => 3,
        "parent_execution_id" => "parent_exec_789",
        "execution_mode" => "sync",
        "status" => "running",
        "trigger_type" => "webhook",
        "trigger_data" => %{"webhook_id" => "wh_123"},
        "vars" => %{"user_id" => "user_456"},
        "node_executions" => %{
          "node_1" => [
            %{
              "node_key" => "node_1",
              "status" => "completed",
              "execution_index" => 0,
              "run_index" => 0,
              "output_data" => %{"result" => "success"},
              "output_port" => "main"
            }
          ]
        },
        "current_execution_index" => 1,
        "suspended_node_id" => "node_2",
        "suspension_type" => "webhook",
        "suspension_data" => %{"webhook_url" => "https://example.com/webhook"},
        "suspended_at" => "2024-01-01T12:00:00Z",
        "started_at" => "2024-01-01T11:00:00Z",
        "completed_at" => "2024-01-01T13:00:00Z",
        "preparation_data" => %{"api_key" => "prepared_key"},
        "metadata" => %{"execution_count" => 5}
      }

      execution = WorkflowExecution.from_map(execution_map)

      assert execution.id == "exec_123"
      assert execution.workflow_id == "wf_456"
      assert execution.workflow_version == 3
      assert execution.parent_execution_id == "parent_exec_789"
      assert execution.execution_mode == :sync
      assert execution.status == :running
      assert execution.trigger_type == "webhook"
      assert execution.trigger_data == %{"webhook_id" => "wh_123"}
      assert execution.vars == %{"user_id" => "user_456"}
      assert execution.current_execution_index == 1
      assert execution.suspended_node_id == "node_2"
      assert execution.suspension_type == "webhook"
      assert execution.suspension_data == %{"webhook_url" => "https://example.com/webhook"}
      assert execution.suspended_at == ~U[2024-01-01 12:00:00Z]
      assert execution.started_at == ~U[2024-01-01 11:00:00Z]
      assert execution.completed_at == ~U[2024-01-01 13:00:00Z]
      assert execution.preparation_data == %{"api_key" => "prepared_key"}
      assert execution.metadata == %{"execution_count" => 5}

      # Check node executions structure
      assert Map.has_key?(execution.node_executions, "node_1")
      node_exec = hd(execution.node_executions["node_1"])
      assert node_exec.node_key == "node_1"
      assert node_exec.status == :completed
      assert node_exec.execution_index == 0
      assert node_exec.run_index == 0
      assert node_exec.output_data == %{"result" => "success"}
      assert node_exec.output_port == "main"
    end

    test "restores workflow execution with minimal required fields" do
      execution_map = %{
        "id" => "exec_minimal",
        "workflow_id" => "wf_minimal"
      }

      execution = WorkflowExecution.from_map(execution_map)

      assert execution.id == "exec_minimal"
      assert execution.workflow_id == "wf_minimal"
      assert execution.workflow_version == 1
      assert execution.parent_execution_id == nil
      assert execution.execution_mode == :async
      assert execution.status == :pending
      assert execution.trigger_type == nil
      assert execution.trigger_data == %{}
      assert execution.vars == %{}
      assert execution.node_executions == %{}
      assert execution.current_execution_index == 0
      assert execution.__runtime == %{}
      assert execution.preparation_data == %{}
      assert execution.metadata == %{}
    end

    test "restores workflow execution with complex node executions" do
      execution_map = %{
        "id" => "exec_complex",
        "workflow_id" => "wf_complex",
        "node_executions" => %{
          "trigger" => [
            %{
              "node_key" => "trigger",
              "status" => "completed",
              "execution_index" => 0,
              "run_index" => 0,
              "output_data" => %{"event" => "user_created"},
              "output_port" => "main"
            }
          ],
          "processor" => [
            %{
              "node_key" => "processor",
              "status" => "failed",
              "execution_index" => 1,
              "run_index" => 0,
              "error_data" => %{"error" => "timeout"},
              "output_port" => nil
            },
            %{
              "node_key" => "processor",
              "status" => "completed",
              "execution_index" => 2,
              "run_index" => 1,
              "output_data" => %{"processed" => true},
              "output_port" => "success"
            }
          ]
        }
      }

      execution = WorkflowExecution.from_map(execution_map)

      assert execution.id == "exec_complex"
      assert execution.workflow_id == "wf_complex"
      
      # Check trigger execution
      trigger_execs = execution.node_executions["trigger"]
      assert length(trigger_execs) == 1
      trigger_exec = hd(trigger_execs)
      assert trigger_exec.node_key == "trigger"
      assert trigger_exec.status == :completed
      assert trigger_exec.output_data == %{"event" => "user_created"}
      
      # Check processor executions (retry scenario)
      processor_execs = execution.node_executions["processor"]
      assert length(processor_execs) == 2
      
      [failed_exec, successful_exec] = processor_execs
      assert failed_exec.status == :failed
      assert failed_exec.run_index == 0
      assert failed_exec.error_data == %{"error" => "timeout"}
      
      assert successful_exec.status == :completed
      assert successful_exec.run_index == 1
      assert successful_exec.output_data == %{"processed" => true}
    end

    test "restores workflow execution with execution graph" do
      execution_graph = %ExecutionGraph{
        workflow_id: "wf_123",
        trigger_node_key: "trigger",
        node_map: %{
          "trigger" => %Node{key: "trigger", name: "Trigger", type: "manual.trigger"},
          "action" => %Node{key: "action", name: "Action", type: "manual.action"}
        },
        connection_map: %{},
        reverse_connection_map: %{}
      }

      execution_map = %{
        "id" => "exec_with_graph",
        "workflow_id" => "wf_123",
        "execution_graph" => execution_graph
      }

      execution = WorkflowExecution.from_map(execution_map)

      assert execution.id == "exec_with_graph"
      assert execution.workflow_id == "wf_123"
      assert execution.execution_graph == execution_graph
      assert execution.execution_graph.workflow_id == "wf_123"
      assert execution.execution_graph.trigger_node_key == "trigger"
      assert Map.has_key?(execution.execution_graph.node_map, "trigger")
      assert Map.has_key?(execution.execution_graph.node_map, "action")
    end

    test "restores workflow execution with all suspension fields" do
      execution_map = %{
        "id" => "exec_suspended",
        "workflow_id" => "wf_suspended",
        "status" => "suspended",
        "suspended_node_id" => "webhook_node",
        "suspension_type" => "webhook",
        "suspension_data" => %{
          "webhook_url" => "https://example.com/webhook/abc123",
          "webhook_id" => "wh_456",
          "timeout_seconds" => 3600
        },
        "suspended_at" => "2024-01-01T14:30:00Z"
      }

      execution = WorkflowExecution.from_map(execution_map)

      assert execution.id == "exec_suspended"
      assert execution.workflow_id == "wf_suspended"
      assert execution.status == :suspended
      assert execution.suspended_node_id == "webhook_node"
      assert execution.suspension_type == "webhook"
      assert execution.suspension_data == %{
        "webhook_url" => "https://example.com/webhook/abc123",
        "webhook_id" => "wh_456",
        "timeout_seconds" => 3600
      }
      assert execution.suspended_at == ~U[2024-01-01 14:30:00Z]
    end

    test "restores workflow execution with runtime state" do
      execution_map = %{
        "id" => "exec_runtime",
        "workflow_id" => "wf_runtime",
        "__runtime" => %{
          "nodes" => %{
            "api_call" => %{"output" => %{"user_id" => 123}},
            "processor" => %{"output" => %{"processed" => true}}
          },
          "env" => %{"api_key" => "test_key"},
          "active_nodes" => ["next_node"],
          "iteration_count" => 5,
          "shared_state" => %{"counter" => 10}
        }
      }

      execution = WorkflowExecution.from_map(execution_map)

      assert execution.id == "exec_runtime"
      assert execution.workflow_id == "wf_runtime"
      assert execution.__runtime == %{
        "nodes" => %{
          "api_call" => %{"output" => %{"user_id" => 123}},
          "processor" => %{"output" => %{"processed" => true}}
        },
        "env" => %{"api_key" => "test_key"},
        "active_nodes" => ["next_node"],
        "iteration_count" => 5,
        "shared_state" => %{"counter" => 10}
      }
    end
  end

  describe "NodeExecution.from_map/1" do
    test "restores node execution from map with string keys" do
      node_execution_map = %{
        "node_key" => "api_call",
        "status" => "completed",
        "params" => %{"method" => "GET", "url" => "https://api.example.com"},
        "output_data" => %{"response" => %{"status" => 200, "body" => "success"}},
        "output_port" => "success",
        "error_data" => nil,
        "started_at" => "2024-01-01T10:00:00Z",
        "completed_at" => "2024-01-01T10:05:00Z",
        "duration_ms" => 5000,
        "execution_index" => 3,
        "run_index" => 1
      }

      node_execution = NodeExecution.from_map(node_execution_map)

      assert node_execution.node_key == "api_call"
      assert node_execution.status == :completed
      assert node_execution.params == %{"method" => "GET", "url" => "https://api.example.com"}
      assert node_execution.output_data == %{"response" => %{"status" => 200, "body" => "success"}}
      assert node_execution.output_port == "success"
      assert node_execution.error_data == nil
      assert node_execution.started_at == ~U[2024-01-01 10:00:00Z]
      assert node_execution.completed_at == ~U[2024-01-01 10:05:00Z]
      assert node_execution.duration_ms == 5000
      assert node_execution.execution_index == 3
      assert node_execution.run_index == 1
    end

    test "restores node execution with minimal required fields" do
      node_execution_map = %{
        "node_key" => "minimal_node"
      }

      node_execution = NodeExecution.from_map(node_execution_map)

      assert node_execution.node_key == "minimal_node"
      assert node_execution.status == :pending
      assert node_execution.params == %{}
      assert node_execution.output_data == nil
      assert node_execution.output_port == nil
      assert node_execution.error_data == nil
      assert node_execution.started_at == nil
      assert node_execution.completed_at == nil
      assert node_execution.duration_ms == nil
      assert node_execution.execution_index == 0
      assert node_execution.run_index == 0
    end

    test "restores failed node execution" do
      node_execution_map = %{
        "node_key" => "failed_node",
        "status" => "failed",
        "error_data" => %{
          "error" => "connection_timeout",
          "message" => "Could not connect to external service",
          "retry_count" => 3
        },
        "output_port" => nil,
        "started_at" => "2024-01-01T10:00:00Z",
        "completed_at" => "2024-01-01T10:01:00Z",
        "duration_ms" => 60000,
        "execution_index" => 2,
        "run_index" => 2
      }

      node_execution = NodeExecution.from_map(node_execution_map)

      assert node_execution.node_key == "failed_node"
      assert node_execution.status == :failed
      assert node_execution.error_data == %{
        "error" => "connection_timeout",
        "message" => "Could not connect to external service",
        "retry_count" => 3
      }
      assert node_execution.output_port == nil
      assert node_execution.started_at == ~U[2024-01-01 10:00:00Z]
      assert node_execution.completed_at == ~U[2024-01-01 10:01:00Z]
      assert node_execution.duration_ms == 60000
      assert node_execution.execution_index == 2
      assert node_execution.run_index == 2
    end

    test "restores suspended node execution" do
      node_execution_map = %{
        "node_key" => "webhook_node",
        "status" => "suspended",
        "params" => %{"webhook_url" => "https://example.com/webhook"},
        "suspension_type" => "webhook",
        "suspension_data" => %{
          "webhook_id" => "wh_123",
          "timeout_seconds" => 3600
        },
        "started_at" => "2024-01-01T10:00:00Z",
        "execution_index" => 1,
        "run_index" => 0
      }

      node_execution = NodeExecution.from_map(node_execution_map)

      assert node_execution.node_key == "webhook_node"
      assert node_execution.status == :suspended
      assert node_execution.params == %{"webhook_url" => "https://example.com/webhook"}
      assert node_execution.suspension_type == "webhook"
      assert node_execution.suspension_data == %{
        "webhook_id" => "wh_123",
        "timeout_seconds" => 3600
      }
      assert node_execution.started_at == ~U[2024-01-01 10:00:00Z]
      assert node_execution.completed_at == nil
      assert node_execution.execution_index == 1
      assert node_execution.run_index == 0
    end

    test "restores node execution with complex params and output" do
      node_execution_map = %{
        "node_key" => "complex_node",
        "status" => "completed",
        "params" => %{
          "conditions" => [
            %{"field" => "user.role", "operator" => "eq", "value" => "admin"},
            %{"field" => "user.active", "operator" => "eq", "value" => true}
          ],
          "logic" => "AND",
          "default_output" => "reject"
        },
        "output_data" => %{
          "matched" => true,
          "result" => "approved",
          "conditions_evaluated" => [
            %{"field" => "user.role", "result" => true},
            %{"field" => "user.active", "result" => true}
          ]
        },
        "output_port" => "approved",
        "execution_index" => 4,
        "run_index" => 0
      }

      node_execution = NodeExecution.from_map(node_execution_map)

      assert node_execution.node_key == "complex_node"
      assert node_execution.status == :completed
      assert node_execution.params["conditions"] == [
        %{"field" => "user.role", "operator" => "eq", "value" => "admin"},
        %{"field" => "user.active", "operator" => "eq", "value" => true}
      ]
      assert node_execution.params["logic"] == "AND"
      assert node_execution.params["default_output"] == "reject"
      assert node_execution.output_data["matched"] == true
      assert node_execution.output_data["result"] == "approved"
      assert node_execution.output_port == "approved"
      assert node_execution.execution_index == 4
      assert node_execution.run_index == 0
    end

    test "restores node execution with all datetime fields" do
      node_execution_map = %{
        "node_key" => "timed_node",
        "status" => "completed",
        "started_at" => "2024-01-01T10:00:00Z",
        "completed_at" => "2024-01-01T10:05:30Z",
        "duration_ms" => 330000,
        "execution_index" => 1,
        "run_index" => 0
      }

      node_execution = NodeExecution.from_map(node_execution_map)

      assert node_execution.node_key == "timed_node"
      assert node_execution.status == :completed
      assert node_execution.started_at == ~U[2024-01-01 10:00:00Z]
      assert node_execution.completed_at == ~U[2024-01-01 10:05:30Z]
      assert node_execution.duration_ms == 330000
      assert node_execution.execution_index == 1
      assert node_execution.run_index == 0
    end
  end

  describe "error handling for execution structs" do
    test "WorkflowExecution.from_map handles invalid data gracefully" do
      # Test with missing required fields - should raise error
      execution_map = %{}
      
      # This should raise an error because id and workflow_id are required
      assert_raise MatchError, fn ->
        WorkflowExecution.from_map(execution_map)
      end
    end

    test "NodeExecution.from_map handles invalid data gracefully" do
      # Test with missing required fields - should raise error
      node_execution_map = %{}
      
      # This should raise an error because node_key is required
      assert_raise MatchError, fn ->
        NodeExecution.from_map(node_execution_map)
      end
    end
  end

  describe "roundtrip serialization for execution structs" do
    test "WorkflowExecution roundtrip serialization preserves data" do
      # Create a workflow execution with complex data
      execution = %WorkflowExecution{
        id: "exec_roundtrip",
        workflow_id: "wf_roundtrip",
        workflow_version: 2,
        execution_mode: :sync,
        status: :suspended,
        trigger_type: "webhook",
        trigger_data: %{"webhook_id" => "wh_123"},
        vars: %{"user_id" => 456},
        node_executions: %{
          "node_1" => [
            %NodeExecution{
              node_key: "node_1",
              status: :completed,
              execution_index: 0,
              run_index: 0,
              output_data: %{"result" => "success"},
              output_port: "main"
            }
          ]
        },
        suspended_node_id: "node_2",
        suspension_type: "webhook",
        suspension_data: %{"webhook_url" => "https://example.com/webhook"},
        metadata: %{"execution_count" => 3}
      }

      # Convert to map (simulating JSON serialization)
      execution_map = WorkflowExecution.to_map(execution)

      # Restore from map
      restored_execution = WorkflowExecution.from_map(execution_map)

      # Verify all data is preserved
      assert restored_execution.id == execution.id
      assert restored_execution.workflow_id == execution.workflow_id
      assert restored_execution.workflow_version == execution.workflow_version
      assert restored_execution.execution_mode == execution.execution_mode
      assert restored_execution.status == execution.status
      assert restored_execution.trigger_type == execution.trigger_type
      assert restored_execution.trigger_data == execution.trigger_data
      assert restored_execution.vars == execution.vars
      assert restored_execution.suspended_node_id == execution.suspended_node_id
      assert restored_execution.suspension_type == execution.suspension_type
      assert restored_execution.suspension_data == execution.suspension_data
      assert restored_execution.metadata == execution.metadata
      
      # Verify node executions are preserved
      assert Map.has_key?(restored_execution.node_executions, "node_1")
      node_exec = hd(restored_execution.node_executions["node_1"])
      assert node_exec.node_key == "node_1"
      assert node_exec.status == :completed
      assert node_exec.execution_index == 0
      assert node_exec.run_index == 0
      assert node_exec.output_data == %{"result" => "success"}
      assert node_exec.output_port == "main"
    end

    test "NodeExecution roundtrip serialization preserves data" do
      # Create a node execution with complex data
      node_execution = %NodeExecution{
        node_key: "complex_node",
        status: :completed,
        params: %{
          "conditions" => [
            %{"field" => "user.role", "operator" => "eq", "value" => "admin"}
          ],
          "logic" => "AND"
        },
        output_data: %{
          "matched" => true,
          "result" => "approved"
        },
        output_port: "approved",
        execution_index: 5,
        run_index: 2
      }

      # Convert to map (simulating JSON serialization)
      node_execution_map = NodeExecution.to_map(node_execution)

      # Restore from map
      restored_node_execution = NodeExecution.from_map(node_execution_map)

      # Verify all data is preserved
      assert restored_node_execution.node_key == node_execution.node_key
      assert restored_node_execution.status == node_execution.status
      assert restored_node_execution.params == node_execution.params
      assert restored_node_execution.output_data == node_execution.output_data
      assert restored_node_execution.output_port == node_execution.output_port
      assert restored_node_execution.execution_index == node_execution.execution_index
      assert restored_node_execution.run_index == node_execution.run_index
    end
  end
end