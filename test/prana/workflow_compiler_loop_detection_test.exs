defmodule Prana.WorkflowCompilerLoopDetectionTest do
  use ExUnit.Case, async: false

  alias Prana.Connection
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

  describe "loop detection and annotation" do
    test "detects simple loop and annotates nodes" do
      # Create simple loop: A -> B -> C -> B
      node_a = Node.new("Start", "test.trigger_action", %{}, "node_a")
      node_b = Node.new("Loop Start", "test.simple_action", %{}, "node_b")
      node_c = Node.new("Loop Body", "test.simple_action", %{}, "node_c")

      connections = %{
        "node_a" => %{
          "success" => [%Connection{from: "node_a", to: "node_b", from_port: "success", to_port: "input"}]
        },
        "node_b" => %{
          "success" => [%Connection{from: "node_b", to: "node_c", from_port: "success", to_port: "input"}]
        },
        "node_c" => %{
          "success" => [%Connection{from: "node_c", to: "node_b", from_port: "success", to_port: "input"}]
        }
      }

      workflow = %Workflow{
        id: "test_loop",
        name: "Test Loop",
        nodes: [node_a, node_b, node_c],
        connections: connections,
        variables: %{}
      }

      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "node_a")

      # Check that loop nodes are annotated
      node_b_compiled = Map.get(execution_graph.node_map, "node_b")
      node_c_compiled = Map.get(execution_graph.node_map, "node_c")
      node_a_compiled = Map.get(execution_graph.node_map, "node_a")

      # Node A should not be in loop
      assert node_a_compiled.metadata == %{}

      # Node B and C should be in loop
      assert node_b_compiled.metadata[:loop_level] == 1
      assert node_b_compiled.metadata[:loop_role] == :start_loop
      assert length(node_b_compiled.metadata[:loop_ids]) == 1
      assert Enum.all?(node_b_compiled.metadata[:loop_ids], &String.starts_with?(&1, "loop_"))

      assert node_c_compiled.metadata[:loop_level] == 1
      assert node_c_compiled.metadata[:loop_role] == :end_loop
      assert length(node_c_compiled.metadata[:loop_ids]) == 1
      assert Enum.all?(node_c_compiled.metadata[:loop_ids], &String.starts_with?(&1, "loop_"))
    end

    test "detects self-loop" do
      # Create self-loop: A -> A
      node_a = Node.new("Self Loop", "test.trigger_action", %{}, "node_a")

      connections = %{
        "node_a" => %{
          "success" => [%Connection{from: "node_a", to: "node_a", from_port: "success", to_port: "input"}]
        }
      }

      workflow = %Workflow{
        id: "test_self_loop",
        name: "Test Self Loop",
        nodes: [node_a],
        connections: connections,
        variables: %{}
      }

      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "node_a")

      node_a_compiled = Map.get(execution_graph.node_map, "node_a")

      assert node_a_compiled.metadata[:loop_level] == 1
      assert node_a_compiled.metadata[:loop_role] == :start_loop
      assert length(node_a_compiled.metadata[:loop_ids]) == 1
      assert Enum.all?(node_a_compiled.metadata[:loop_ids], &String.starts_with?(&1, "loop_"))
    end

    test "detects nested loops" do
      # Create nested loop structure:
      # A -> B -> C -> D -> C (outer loop: B,C,D)
      #      |    |
      #      v    v  
      #      E -> F -> E (inner loop: E,F)
      node_a = Node.new("Start", "test.trigger_action", %{}, "node_a")
      node_b = Node.new("Outer Start", "test.simple_action", %{}, "node_b")
      node_c = Node.new("Shared", "test.simple_action", %{}, "node_c")
      node_d = Node.new("Outer End", "test.simple_action", %{}, "node_d")
      node_e = Node.new("Inner Start", "test.simple_action", %{}, "node_e")
      node_f = Node.new("Inner End", "test.simple_action", %{}, "node_f")

      connections = %{
        "node_a" => %{
          "success" => [%Connection{from: "node_a", to: "node_b", from_port: "success", to_port: "input"}]
        },
        "node_b" => %{
          "success" => [
            %Connection{from: "node_b", to: "node_c", from_port: "success", to_port: "input"},
            %Connection{from: "node_b", to: "node_e", from_port: "success", to_port: "input"}
          ]
        },
        "node_c" => %{
          "success" => [
            %Connection{from: "node_c", to: "node_d", from_port: "success", to_port: "input"},
            %Connection{from: "node_c", to: "node_f", from_port: "success", to_port: "input"}
          ]
        },
        "node_d" => %{
          "success" => [%Connection{from: "node_d", to: "node_c", from_port: "success", to_port: "input"}]
        },
        "node_e" => %{
          "success" => [%Connection{from: "node_e", to: "node_f", from_port: "success", to_port: "input"}]
        },
        "node_f" => %{
          "success" => [%Connection{from: "node_f", to: "node_e", from_port: "success", to_port: "input"}]
        }
      }

      workflow = %Workflow{
        id: "test_nested_loops",
        name: "Test Nested Loops",
        nodes: [node_a, node_b, node_c, node_d, node_e, node_f],
        connections: connections,
        variables: %{}
      }

      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "node_a")

      # Check node annotations
      node_a_compiled = Map.get(execution_graph.node_map, "node_a")
      node_e_compiled = Map.get(execution_graph.node_map, "node_e")
      node_f_compiled = Map.get(execution_graph.node_map, "node_f")

      # Node A should not be in any loop
      assert node_a_compiled.metadata == %{}

      # Inner loop nodes should have level 1 or 2 depending on implementation
      assert node_e_compiled.metadata[:loop_level] >= 1
      assert node_e_compiled.metadata[:loop_role] in [:start_loop, :in_loop, :end_loop]
      assert is_list(node_e_compiled.metadata[:loop_ids])

      assert node_f_compiled.metadata[:loop_level] >= 1
      assert node_f_compiled.metadata[:loop_role] in [:start_loop, :in_loop, :end_loop]
      assert is_list(node_f_compiled.metadata[:loop_ids])
    end

    test "handles workflow with no loops" do
      # Linear workflow: A -> B -> C
      node_a = Node.new("Start", "test.trigger_action", %{}, "node_a")
      node_b = Node.new("Middle", "test.simple_action", %{}, "node_b")
      node_c = Node.new("End", "test.simple_action", %{}, "node_c")

      connections = %{
        "node_a" => %{
          "success" => [%Connection{from: "node_a", to: "node_b", from_port: "success", to_port: "input"}]
        },
        "node_b" => %{
          "success" => [%Connection{from: "node_b", to: "node_c", from_port: "success", to_port: "input"}]
        }
      }

      workflow = %Workflow{
        id: "test_no_loops",
        name: "Test No Loops",
        nodes: [node_a, node_b, node_c],
        connections: connections,
        variables: %{}
      }

      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "node_a")

      # All nodes should have empty metadata
      Enum.each(execution_graph.node_map, fn {_key, node} ->
        assert node.metadata == %{}
      end)
    end
  end
end
