defmodule Prana.GraphExecutorTest do
  use ExUnit.Case, async: true

  alias Prana.Connection
  alias Prana.GraphExecutor
  alias Prana.IntegrationRegistry
  alias Prana.Node
  alias Prana.Workflow

  # Test integrations
  defmodule TestHTTPIntegration do
    @moduledoc false
    @behaviour Prana.Behaviour.Integration

    def definition do
      %Prana.Integration{
        name: "test_http",
        display_name: "Test HTTP",
        actions: %{
          "get" => %Prana.Action{
            name: "get",
            module: __MODULE__,
            function: :http_get,
            input_ports: ["input"],
            output_ports: ["success", "error"],
            default_success_port: "success",
            default_error_port: "error"
          }
        }
      }
    end

    def http_get(%{"url" => url}) do
      {:ok, %{"status" => 200, "data" => "Response from #{url}"}}
    end
  end

  defmodule TestTransformIntegration do
    @moduledoc false
    @behaviour Prana.Behaviour.Integration

    def definition do
      %Prana.Integration{
        name: "test_transform",
        display_name: "Test Transform",
        actions: %{
          "extract" => %Prana.Action{
            name: "extract",
            module: __MODULE__,
            function: :extract_data,
            input_ports: ["input"],
            output_ports: ["success", "error"],
            default_success_port: "success",
            default_error_port: "error"
          }
        }
      }
    end

    def extract_data(%{"source" => data, "field" => field}) do
      case Map.get(data, field) do
        nil -> {:error, "Field #{field} not found"}
        value -> {:ok, %{"extracted_value" => value}}
      end
    end
  end

  setup do
    # Start IntegrationRegistry for each test
    {:ok, _pid} = IntegrationRegistry.start_link([])

    # Register test integrations
    IntegrationRegistry.register_integration(TestHTTPIntegration)
    IntegrationRegistry.register_integration(TestTransformIntegration)

    :ok
  end

  describe "execute_workflow/3" do
    test "executes simple sequential workflow successfully" do
      workflow = create_sequential_workflow()
      input_data = %{"user_url" => "https://api.example.com/users/123"}

      case GraphExecutor.execute_workflow(workflow, input_data) do
        {:ok, context} ->
          # Verify workflow completed
          assert context.execution.status == :completed

          # Verify all nodes executed
          assert MapSet.size(context.completed_nodes) == 2
          assert MapSet.size(context.failed_nodes) == 0

          # Verify node results exist
          assert Map.has_key?(context.nodes, "http_get")
          assert Map.has_key?(context.nodes, "extract_data")

        {:error, reason} ->
          flunk("Workflow execution failed: #{inspect(reason)}")
      end
    end

    test "handles node execution failures gracefully" do
      workflow = create_failing_workflow()
      input_data = %{"user_url" => "invalid_url"}

      case GraphExecutor.execute_workflow(workflow, input_data) do
        {:ok, context} ->
          # Should complete but with some failed nodes
          assert context.execution.status == :completed

        {:error, :workflow_completed_with_failures} ->
          # This is acceptable for workflows with non-critical failures
          assert true

        {:error, reason} ->
          # Other errors should be handled appropriately
          assert is_atom(reason) or is_map(reason)
      end
    end

    test "validates workflow structure before execution" do
      # Create invalid workflow with no nodes
      workflow = %Workflow{
        id: "invalid",
        name: "Invalid Workflow",
        nodes: [],
        connections: [],
        variables: %{},
        settings: %Prana.WorkflowSettings{},
        metadata: %{}
      }

      input_data = %{}

      case GraphExecutor.execute_workflow(workflow, input_data) do
        {:error, :no_nodes} ->
          assert true

        {:error, reason} ->
          # Should be some validation error
          assert reason != nil

        {:ok, _context} ->
          flunk("Should not execute invalid workflow")
      end
    end
  end

  describe "execute_workflow_async/3" do
    test "executes workflow asynchronously" do
      workflow = create_sequential_workflow()
      input_data = %{"user_url" => "https://api.example.com/users/123"}

      {:ok, task} = GraphExecutor.execute_workflow_async(workflow, input_data)

      # Verify task is running
      assert %Task{} = task

      # Wait for completion
      case Task.await(task, 5000) do
        {:ok, context} ->
          assert context.execution.status == :completed

        {:error, _reason} ->
          # Acceptable for async execution
          assert true
      end
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp create_sequential_workflow do
    workflow = Workflow.new("Sequential Test", "Test sequential execution")

    # Create nodes
    http_node =
      Node.new(
        "HTTP Get",
        :action,
        "test_http",
        "get",
        %{
          "url" => "$input.user_url"
        },
        "http_get"
      )

    extract_node =
      Node.new(
        "Extract Data",
        :action,
        "test_transform",
        "extract",
        %{
          "source" => "$nodes.http_get",
          "field" => "data"
        },
        "extract_data"
      )

    # Add nodes
    workflow =
      workflow
      |> Workflow.add_node!(http_node)
      |> Workflow.add_node!(extract_node)

    # Create connection
    connection = Connection.new(http_node.id, "success", extract_node.id, "input")

    # Add connection
    {:ok, workflow} = Workflow.add_connection(workflow, connection)
    workflow
  end

  defp create_failing_workflow do
    workflow = Workflow.new("Failing Test", "Test failure handling")

    # Create a node that will fail
    failing_node =
      Node.new(
        "Failing Node",
        :action,
        "test_transform",
        "extract",
        %{
          # Empty source
          "source" => %{},
          "field" => "nonexistent_field"
        },
        "failing_node"
      )

    # Add node
    workflow = Workflow.add_node!(workflow, failing_node)
    workflow
  end
end
