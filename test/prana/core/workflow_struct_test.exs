defmodule Prana.Core.WorkflowStructTest do
  use ExUnit.Case, async: true

  alias Prana.Connection
  alias Prana.Node
  alias Prana.Workflow

  describe "Workflow.from_map/1" do
    test "restores workflow from basic map with string keys" do
      workflow_map = %{
        "id" => "wf_123",
        "name" => "Test Workflow",
        "description" => "A test workflow",
        "version" => 2,
        "nodes" => [
          %{
            "key" => "node_1",
            "name" => "First Node",
            "type" => "manual.test",
            "params" => %{"value" => "test"}
          }
        ],
        "connections" => %{
          "node_1" => %{
            "output" => [
              %{
                "from" => "node_1",
                "from_port" => "output",
                "to" => "node_2",
                "to_port" => "input"
              }
            ]
          }
        },
        "variables" => %{"env" => "test"}
      }

      workflow = Workflow.from_map(workflow_map)

      assert workflow.id == "wf_123"
      assert workflow.name == "Test Workflow"
      assert workflow.description == "A test workflow"
      assert workflow.version == 2
      assert length(workflow.nodes) == 1
      assert workflow.variables == %{"env" => "test"}

      node = hd(workflow.nodes)
      assert node.key == "node_1"
      assert node.name == "First Node"
      assert node.type == "manual.test"
      assert node.params == %{"value" => "test"}

      # Check connections structure
      assert Map.has_key?(workflow.connections, "node_1")
      assert Map.has_key?(workflow.connections["node_1"], "output")
      connection = hd(workflow.connections["node_1"]["output"])
      assert connection.from == "node_1"
      assert connection.from_port == "output"
      assert connection.to == "node_2"
      assert connection.to_port == "input"
    end

    test "restores workflow with minimal required fields" do
      workflow_map = %{
        "id" => "wf_minimal",
        "name" => "Minimal Workflow"
      }

      workflow = Workflow.from_map(workflow_map)

      assert workflow.id == "wf_minimal"
      assert workflow.name == "Minimal Workflow"
      assert workflow.description == nil
      assert workflow.version == 1
      assert workflow.nodes == []
      assert workflow.connections == %{}
      assert workflow.variables == %{}
    end

    test "restores workflow with empty collections" do
      workflow_map = %{
        "id" => "wf_empty",
        "name" => "Empty Workflow",
        "nodes" => [],
        "connections" => %{},
        "variables" => %{}
      }

      workflow = Workflow.from_map(workflow_map)

      assert workflow.id == "wf_empty"
      assert workflow.name == "Empty Workflow"
      assert workflow.nodes == []
      assert workflow.connections == %{}
      assert workflow.variables == %{}
    end

    test "restores workflow with complex nested connections" do
      workflow_map = %{
        "id" => "wf_complex",
        "name" => "Complex Workflow",
        "connections" => %{
          "trigger" => %{
            "main" => [
              %{
                "from" => "trigger",
                "from_port" => "main",
                "to" => "process",
                "to_port" => "input"
              }
            ]
          },
          "process" => %{
            "success" => [
              %{
                "from" => "process",
                "from_port" => "success",
                "to" => "notify",
                "to_port" => "main"
              }
            ],
            "error" => [
              %{
                "from" => "process",
                "from_port" => "error",
                "to" => "log_error",
                "to_port" => "main"
              }
            ]
          }
        }
      }

      workflow = Workflow.from_map(workflow_map)

      assert workflow.id == "wf_complex"
      assert workflow.name == "Complex Workflow"

      # Check nested connections structure
      assert Map.has_key?(workflow.connections, "trigger")
      assert Map.has_key?(workflow.connections["trigger"], "main")
      assert Map.has_key?(workflow.connections, "process")
      assert Map.has_key?(workflow.connections["process"], "success")
      assert Map.has_key?(workflow.connections["process"], "error")

      trigger_conn = hd(workflow.connections["trigger"]["main"])
      assert trigger_conn.from == "trigger"
      assert trigger_conn.to == "process"

      success_conn = hd(workflow.connections["process"]["success"])
      assert success_conn.from == "process"
      assert success_conn.to == "notify"

      error_conn = hd(workflow.connections["process"]["error"])
      assert error_conn.from == "process"
      assert error_conn.to == "log_error"
    end
  end

  describe "Node.from_map/1" do
    test "restores node from map with string keys" do
      node_map = %{
        "key" => "api_call",
        "name" => "API Call Node",
        "type" => "http.request",
        "params" => %{
          "method" => "GET",
          "url" => "https://api.example.com/users",
          "headers" => %{"Authorization" => "Bearer token"}
        }
      }

      node = Node.from_map(node_map)

      assert node.key == "api_call"
      assert node.name == "API Call Node"
      assert node.type == "http.request"

      assert node.params == %{
               "method" => "GET",
               "url" => "https://api.example.com/users",
               "headers" => %{"Authorization" => "Bearer token"}
             }
    end

    test "restores node with minimal required fields" do
      node_map = %{
        "key" => "minimal_node",
        "type" => "manual.test"
      }

      node = Node.from_map(node_map)

      assert node.key == "minimal_node"
      assert node.name == nil
      assert node.type == "manual.test"
      assert node.params == %{}
    end

    test "restores node with empty params" do
      node_map = %{
        "key" => "empty_params",
        "name" => "Empty Params Node",
        "type" => "logic.condition",
        "params" => %{}
      }

      node = Node.from_map(node_map)

      assert node.key == "empty_params"
      assert node.name == "Empty Params Node"
      assert node.type == "logic.condition"
      assert node.params == %{}
    end

    test "restores node with complex nested params" do
      node_map = %{
        "key" => "complex_node",
        "name" => "Complex Node",
        "type" => "data.transform",
        "params" => %{
          "mappings" => [
            %{"from" => "input.user.id", "to" => "user_id"},
            %{"from" => "input.user.name", "to" => "full_name"}
          ],
          "filters" => %{
            "status" => "active",
            "role" => ["admin", "user"]
          },
          "options" => %{
            "strict" => true,
            "default_value" => nil
          }
        }
      }

      node = Node.from_map(node_map)

      assert node.key == "complex_node"
      assert node.name == "Complex Node"
      assert node.type == "data.transform"

      assert node.params["mappings"] == [
               %{"from" => "input.user.id", "to" => "user_id"},
               %{"from" => "input.user.name", "to" => "full_name"}
             ]

      assert node.params["filters"] == %{
               "status" => "active",
               "role" => ["admin", "user"]
             }

      assert node.params["options"] == %{
               "strict" => true,
               "default_value" => nil
             }
    end
  end

  describe "Connection.from_map/1" do
    test "restores connection from map with string keys" do
      connection_map = %{
        "from" => "source_node",
        "from_port" => "success",
        "to" => "target_node",
        "to_port" => "input"
      }

      connection = Connection.from_map(connection_map)

      assert connection.from == "source_node"
      assert connection.from_port == "success"
      assert connection.to == "target_node"
      assert connection.to_port == "input"
    end

    test "restores connection with minimal required fields" do
      connection_map = %{
        "from" => "node_a",
        "to" => "node_b"
      }

      connection = Connection.from_map(connection_map)

      assert connection.from == "node_a"
      assert connection.from_port == "main"
      assert connection.to == "node_b"
      assert connection.to_port == "main"
    end

    test "restores connection with default port values" do
      connection_map = %{
        "from" => "start",
        "from_port" => "output",
        "to" => "end"
      }

      connection = Connection.from_map(connection_map)

      assert connection.from == "start"
      assert connection.from_port == "output"
      assert connection.to == "end"
      assert connection.to_port == "main"
    end
  end

  describe "error handling for workflow structs" do
    test "Node.from_map handles invalid data gracefully" do
      # Test with missing required fields - should raise error
      node_map = %{}

      # This should raise an error because key and type are required
      assert_raise MatchError, fn ->
        Node.from_map(node_map)
      end
    end

    test "Connection.from_map handles invalid data gracefully" do
      # Test with missing required fields - should raise error
      connection_map = %{}

      # This should raise an error because from and to are required
      assert_raise MatchError, fn ->
        Connection.from_map(connection_map)
      end
    end

    test "Workflow.from_map handles invalid data gracefully" do
      # Test with missing required fields - should raise error
      workflow_map = %{}

      # This should raise an error because id and name are required
      assert_raise MatchError, fn ->
        Workflow.from_map(workflow_map)
      end
    end
  end

  describe "roundtrip serialization for workflow structs" do
    test "Workflow roundtrip serialization preserves data" do
      # Create a workflow with complex data
      workflow = %Workflow{
        id: "wf_roundtrip",
        name: "Roundtrip Test",
        description: "Test workflow for roundtrip serialization",
        version: 2,
        nodes: [
          %Node{key: "n1", name: "Node 1", type: "manual.test", params: %{"value" => 123}},
          %Node{key: "n2", name: "Node 2", type: "logic.condition", params: %{"condition" => "true"}}
        ],
        connections: %{
          "n1" => %{
            "output" => [%Connection{from: "n1", from_port: "output", to: "n2", to_port: "input"}]
          }
        },
        variables: %{"test_var" => "test_value"}
      }

      # Convert to map (simulating JSON serialization)
      workflow_map = Workflow.to_map(workflow)

      # Restore from map
      restored_workflow = Workflow.from_map(workflow_map)

      # Verify all data is preserved
      assert restored_workflow.id == workflow.id
      assert restored_workflow.name == workflow.name
      assert restored_workflow.description == workflow.description
      assert restored_workflow.version == workflow.version
      assert length(restored_workflow.nodes) == length(workflow.nodes)
      assert restored_workflow.variables == workflow.variables

      # Verify nodes are preserved
      [n1, n2] = restored_workflow.nodes
      assert n1.key == "n1"
      assert n1.name == "Node 1"
      assert n1.type == "manual.test"
      assert n1.params == %{"value" => 123}

      assert n2.key == "n2"
      assert n2.name == "Node 2"
      assert n2.type == "logic.condition"
      assert n2.params == %{"condition" => "true"}

      # Verify connections are preserved
      assert Map.has_key?(restored_workflow.connections, "n1")
      conn = hd(restored_workflow.connections["n1"]["output"])
      assert conn.from == "n1"
      assert conn.from_port == "output"
      assert conn.to == "n2"
      assert conn.to_port == "input"
    end

    test "Node roundtrip serialization preserves data" do
      # Create a node with complex params
      node = %Node{
        key: "complex_node",
        name: "Complex Node",
        type: "data.transform",
        params: %{
          "mappings" => [
            %{"from" => "input.user.id", "to" => "user_id"},
            %{"from" => "input.user.name", "to" => "full_name"}
          ],
          "filters" => %{
            "status" => "active",
            "role" => ["admin", "user"]
          }
        }
      }

      # Convert to map (simulating JSON serialization)
      node_map = Node.to_map(node)

      # Restore from map
      restored_node = Node.from_map(node_map)

      # Verify all data is preserved
      assert restored_node.key == node.key
      assert restored_node.name == node.name
      assert restored_node.type == node.type
      assert restored_node.params == node.params
    end

    test "Connection roundtrip serialization preserves data" do
      # Create a connection
      connection = %Connection{
        from: "source_node",
        from_port: "success",
        to: "target_node",
        to_port: "input"
      }

      # Convert to map (simulating JSON serialization)
      connection_map = Connection.to_map(connection)

      # Restore from map
      restored_connection = Connection.from_map(connection_map)

      # Verify all data is preserved
      assert restored_connection.from == connection.from
      assert restored_connection.from_port == connection.from_port
      assert restored_connection.to == connection.to
      assert restored_connection.to_port == connection.to_port
    end
  end
end
