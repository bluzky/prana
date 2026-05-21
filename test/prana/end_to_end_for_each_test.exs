defmodule Prana.EndToEndForEachTest do
  use ExUnit.Case, async: false

  alias Prana.Actions.SimpleAction
  alias Prana.Connection
  alias Prana.GraphExecutor
  alias Prana.IntegrationRegistry
  alias Prana.Integrations.Core
  alias Prana.Integrations.Manual
  alias Prana.Node
  alias Prana.Workflow
  alias Prana.WorkflowCompiler

  # Collects processed items into the agent during loop execution
  defmodule ItemCollectorAction do
    @moduledoc false
    use SimpleAction

    alias Prana.Action

    def definition do
      %Action{
        name: "test.item_collector",
        display_name: "Item Collector",
        type: :action,
        module: __MODULE__,
        input_ports: ["main"],
        output_ports: ["main"]
      }
    end

    @impl true
    def execute(_params, context) do
      item = get_in(context, ["$input", "main"])
      {:ok, %{"collected" => item}}
    end
  end

  defmodule TestCollectorIntegration do
    @moduledoc false
    @behaviour Prana.Behaviour.Integration

    def definition do
      %Prana.Integration{
        name: "test",
        display_name: "Test Integration",
        actions: [ItemCollectorAction]
      }
    end
  end

  defp convert_connections_to_map(workflow) do
    connections_list = workflow.connections
    workflow_with_empty_connections = %{workflow | connections: %{}}

    Enum.reduce(connections_list, workflow_with_empty_connections, fn connection, acc_workflow ->
      {:ok, updated_workflow} = Workflow.add_connection(acc_workflow, connection)
      updated_workflow
    end)
  end

  setup do
    Code.ensure_loaded!(Manual)
    Code.ensure_loaded!(Core)

    registry_pid =
      case IntegrationRegistry.start_link() do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    IntegrationRegistry.register_integration(Manual)
    IntegrationRegistry.register_integration(Core)
    IntegrationRegistry.register_integration(TestCollectorIntegration)

    on_exit(fn ->
      if Process.alive?(registry_pid) do
        GenServer.stop(registry_pid)
      end
    end)

    :ok
  end

  # Runs the workflow, resuming on each loopback suspension until complete
  defp run_to_completion(execution_graph, input, max_iterations \\ 20) do
    case GraphExecutor.execute_workflow(execution_graph, input) do
      {:ok, execution, output} -> {:ok, execution, output}
      {:suspend, suspended, data} -> resume_loop(suspended, data, max_iterations, 0)
      {:error, _} = err -> err
    end
  end

  defp resume_loop(_suspended, _data, max_iterations, count) when count >= max_iterations do
    {:error, :max_iterations_exceeded}
  end

  defp resume_loop(suspended, _data, max_iterations, count) do
    case GraphExecutor.resume_workflow(suspended, %{}) do
      {:ok, execution, output} -> {:ok, execution, output}
      {:suspend, suspended2, data2} -> resume_loop(suspended2, data2, max_iterations, count + 1)
      {:error, _} = err -> err
    end
  end

  describe "end-to-end for_each single mode" do
    test "iterates through all items and completes" do
      workflow =
        %Workflow{
          id: "for_each_single_e2e",
          name: "ForEach Single E2E",
          nodes: [
            %Node{key: "trigger", name: "Start", type: "manual.trigger"},
            %Node{key: "loop", name: "For Each", type: "prana_core.for_each",
                  params: %{"collection" => [1, 2, 3], "mode" => "single"}},
            %Node{key: "collector", name: "Collector", type: "test.item_collector"}
          ],
          connections: [
            Connection.new("trigger", "main", "loop", "main"),
            Connection.new("loop", "loop", "collector", "main"),
            Connection.new("collector", "main", "loop", "main")
          ]
        }
        |> convert_connections_to_map()

      {:ok, execution_graph} = WorkflowCompiler.compile(workflow)

      assert {:ok, execution, _output} = run_to_completion(execution_graph, %{})
      assert execution.status == "completed"
    end

    test "processes each item individually" do
      collection = ["a", "b", "c"]

      workflow =
        %Workflow{
          id: "for_each_items_e2e",
          name: "ForEach Items E2E",
          nodes: [
            %Node{key: "trigger", name: "Start", type: "manual.trigger"},
            %Node{key: "loop", name: "For Each", type: "prana_core.for_each",
                  params: %{"collection" => collection, "mode" => "single"}},
            %Node{key: "collector", name: "Collector", type: "test.item_collector"}
          ],
          connections: [
            Connection.new("trigger", "main", "loop", "main"),
            Connection.new("loop", "loop", "collector", "main"),
            Connection.new("collector", "main", "loop", "main")
          ]
        }
        |> convert_connections_to_map()

      {:ok, execution_graph} = WorkflowCompiler.compile(workflow)

      assert {:ok, execution, _output} = run_to_completion(execution_graph, %{})
      assert execution.status == "completed"

      # Verify collector ran once per item
      collector_executions = Map.get(execution.node_executions, "collector", [])
      assert length(collector_executions) == length(collection)
    end

    test "completes immediately on empty collection" do
      workflow =
        %Workflow{
          id: "for_each_empty_e2e",
          name: "ForEach Empty E2E",
          nodes: [
            %Node{key: "trigger", name: "Start", type: "manual.trigger"},
            %Node{key: "loop", name: "For Each", type: "prana_core.for_each",
                  params: %{"collection" => [], "mode" => "single"}}
          ],
          connections: [
            Connection.new("trigger", "main", "loop", "main")
          ]
        }
        |> convert_connections_to_map()

      {:ok, execution_graph} = WorkflowCompiler.compile(workflow)

      assert {:ok, execution, _output} = run_to_completion(execution_graph, %{})
      assert execution.status == "completed"
    end
  end

  describe "end-to-end for_each batch mode" do
    test "iterates through all batches and completes" do
      workflow =
        %Workflow{
          id: "for_each_batch_e2e",
          name: "ForEach Batch E2E",
          nodes: [
            %Node{key: "trigger", name: "Start", type: "manual.trigger"},
            %Node{key: "loop", name: "For Each", type: "prana_core.for_each",
                  params: %{"collection" => [1, 2, 3, 4, 5], "mode" => "batch", "batch_size" => 2}},
            %Node{key: "collector", name: "Collector", type: "test.item_collector"}
          ],
          connections: [
            Connection.new("trigger", "main", "loop", "main"),
            Connection.new("loop", "loop", "collector", "main"),
            Connection.new("collector", "main", "loop", "main")
          ]
        }
        |> convert_connections_to_map()

      {:ok, execution_graph} = WorkflowCompiler.compile(workflow)

      assert {:ok, execution, _output} = run_to_completion(execution_graph, %{})
      assert execution.status == "completed"

      # 5 items with batch_size 2 → 3 batches ([1,2], [3,4], [5])
      collector_executions = Map.get(execution.node_executions, "collector", [])
      assert length(collector_executions) == 3
    end
  end
end
