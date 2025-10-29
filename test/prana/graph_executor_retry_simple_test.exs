defmodule Prana.GraphExecutorRetrySimpleTest do
  use ExUnit.Case, async: false

  alias Prana.Actions.SimpleAction
  alias Prana.ExecutionGraph
  alias Prana.GraphExecutor
  alias Prana.IntegrationRegistry
  alias Prana.Integrations.Manual
  alias Prana.Integrations.Wait
  alias Prana.Node
  alias Prana.NodeSettings
  alias Prana.WorkflowExecution

  # Test actions for retry integration testing
  defmodule FailOnceAction do
    @moduledoc false
    use SimpleAction

    alias Prana.Action
    alias Prana.Core.Error

    def definition do
      %Action{
        name: "retry.fail_once",
        display_name: "Fail Once",
        description: "Fails on first attempt, succeeds on retry",
        type: :action,
        module: __MODULE__,
        input_ports: ["main"],
        output_ports: ["main"]
      }
    end

    @impl true
    def execute(_params, context) do
      # Check if this is a retry by looking at the execution state
      retry_count = get_in(context, ["$execution", "state", "retry_count"]) || 0

      if retry_count == 0 do
        # First attempt - fail
        {:error, Error.new("action_error", "First attempt fails", %{error: "First attempt fails"})}
      else
        # Retry attempt - succeed
        {:ok, %{message: "Success on retry", attempt: retry_count}}
      end
    end
  end

  defmodule AlwaysFailAction do
    @moduledoc false
    use SimpleAction

    alias Prana.Action
    alias Prana.Core.Error

    def definition do
      %Action{
        name: "retry.always_fail",
        display_name: "Always Fail",
        description: "Always fails for max retry testing",
        type: :action,
        module: __MODULE__,
        input_ports: ["main"],
        output_ports: ["main"]
      }
    end

    @impl true
    def execute(_params, _context) do
      {:error, Error.new("action_error", "Always fails", %{error: "Always fails"})}
    end
  end

  defmodule RetryTestIntegration do
    @moduledoc false
    @behaviour Prana.Behaviour.Integration

    def definition do
      %Prana.Integration{
        name: "retry",
        display_name: "Retry Test Integration",
        actions: [
          FailOnceAction,
          AlwaysFailAction
        ]
      }
    end
  end

  setup do
    # Ensure modules are loaded before registration
    Code.ensure_loaded!(Wait)
    Code.ensure_loaded!(Manual)

    # Start IntegrationRegistry or get existing process
    registry_pid =
      case IntegrationRegistry.start_link() do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    # Register test integration
    IntegrationRegistry.register_integration(RetryTestIntegration)

    # Register Wait integration for webhook tests
    IntegrationRegistry.register_integration(Wait)

    # Register Manual integration for trigger nodes
    IntegrationRegistry.register_integration(Manual)

    # Clean up registry on exit only if we started it
    on_exit(fn ->
      # Only stop if we started it and it's still the same process
      if Process.alive?(registry_pid) do
        case Process.info(registry_pid, :registered_name) do
          {:registered_name, IntegrationRegistry} ->
            # This is the named registry - don't stop it as other tests might need it
            :ok

          _ ->
            # This is an unnamed process we started - safe to stop
            GenServer.stop(registry_pid)
        end
      end
    end)

    :ok
  end

  describe "GraphExecutor retry decision logic" do
    test "resume_suspended_node calls retry_node for retry suspensions" do
      # Create a manual execution graph structure for testing
      settings = NodeSettings.new(%{retry_on_failed: true, max_retries: 2, retry_delay_ms: 100})
      retry_node = %{Node.new("Retry Node", "retry.fail_once") | settings: settings}

      execution_graph = %ExecutionGraph{
        workflow_id: "test_workflow",
        trigger_node_key: "trigger",
        dependency_graph: %{},
        connection_map: %{},
        reverse_connection_map: %{},
        node_map: %{
          "trigger" => Node.new("Trigger", "manual.trigger"),
          "retry_node" => retry_node
        },
        variables: %{}
      }

      # Create a suspended execution with retry suspension
      suspended_execution = %WorkflowExecution{
        id: "test_execution",
        workflow_id: "test_workflow",
        workflow_version: 1,
        execution_mode: :async,
        status: "suspended",
        suspended_node_id: "retry_node",
        vars: %{},
        node_executions: %{
          "retry_node" => [
            %Prana.NodeExecution{
              node_key: "retry_node",
              execution_index: 1,
              run_index: 0,
              status: "suspended",
              suspension_type: :retry,
              suspension_data: %{
                "attempt_number" => 1,
                "max_attempts" => 2,
                "resume_at" => DateTime.add(DateTime.utc_now(), 100, :millisecond)
              }
            }
          ]
        },
        execution_graph: execution_graph,
        __runtime: %{
          "nodes" => %{},
          "env" => %{},
          "active_paths" => %{},
          "executed_nodes" => []
        },
        execution_data: %{
          "context_data" => %{
            "workflow" => %{"retry_count" => 1},
            "node" => %{}
          },
          "active_paths" => %{},
          "active_nodes" => %{}
        }
      }

      # Resume should detect retry suspension and call retry_node
      result = GraphExecutor.resume_workflow(suspended_execution, %{})

      # Should complete (our test action succeeds on retry)
      assert {:ok, completed_execution, _output} = result
      assert completed_execution.status == "completed"
    end

    test "resume_suspended_node calls resume_node for regular suspensions" do
      # Create execution with webhook suspension
      execution_graph = %ExecutionGraph{
        workflow_id: "test_workflow",
        trigger_node_key: "trigger",
        dependency_graph: %{},
        connection_map: %{},
        reverse_connection_map: %{},
        node_map: %{
          "trigger" => Node.new("Trigger", "manual.trigger"),
          "wait_node" => Node.new("Wait Node", "wait.wait")
        },
        variables: %{}
      }

      suspended_execution = %WorkflowExecution{
        id: "test_execution",
        workflow_id: "test_workflow",
        workflow_version: 1,
        execution_mode: :async,
        status: "suspended",
        suspended_node_id: "wait_node",
        vars: %{},
        node_executions: %{
          "wait_node" => [
            %Prana.NodeExecution{
              node_key: "wait_node",
              execution_index: 1,
              run_index: 0,
              status: "suspended",
              suspension_type: :webhook,
              suspension_data: %{
                "timeout_hours" => 1,
                "webhook_id" => "test_webhook"
              },
              params: %{
                "mode" => "webhook",
                "timeout_hours" => 1
              }
            }
          ]
        },
        execution_graph: execution_graph,
        __runtime: %{
          "nodes" => %{},
          "env" => %{},
          "active_paths" => %{},
          "executed_nodes" => []
        },
        execution_data: %{
          "context_data" => %{
            "workflow" => %{},
            "node" => %{}
          },
          "active_paths" => %{},
          "active_nodes" => %{}
        }
      }

      # Resume with webhook data - should call resume_node (not retry_node)
      resume_data = %{"webhook_payload" => %{"result" => "webhook received"}}
      result = GraphExecutor.resume_workflow(suspended_execution, resume_data)

      # Should complete successfully using regular resume logic
      assert {:ok, completed_execution, _output} = result
      assert completed_execution.status == "completed"
    end

    test "retry_node can return another suspension for multiple retries" do
      # This test verifies that GraphExecutor handles the case where retry_node
      # returns another suspension (for further retry attempts)

      # Create manual execution with a node that will fail multiple times
      settings = NodeSettings.new(%{retry_on_failed: true, max_retries: 3, retry_delay_ms: 100})
      always_fail_node = %{Node.new("Always Fail", "retry.always_fail") | settings: settings}

      execution_graph = %ExecutionGraph{
        workflow_id: "test_workflow",
        trigger_node_key: "trigger",
        dependency_graph: %{},
        connection_map: %{},
        reverse_connection_map: %{},
        node_map: %{
          "trigger" => Node.new("Trigger", "manual.trigger"),
          "always_fail" => always_fail_node
        },
        variables: %{}
      }

      # Create suspended execution at attempt 1 (still has retries left)
      suspended_execution = %WorkflowExecution{
        id: "test_execution",
        workflow_id: "test_workflow",
        workflow_version: 1,
        execution_mode: :async,
        status: "suspended",
        suspended_node_id: "always_fail",
        vars: %{},
        node_executions: %{
          "always_fail" => [
            %Prana.NodeExecution{
              node_key: "always_fail",
              execution_index: 1,
              run_index: 0,
              status: "suspended",
              suspension_type: :retry,
              suspension_data: %{
                "attempt_number" => 1,
                "max_attempts" => 3,
                "resume_at" => DateTime.add(DateTime.utc_now(), 100, :millisecond),
                "original_error" =>
                  Prana.Core.Error.new("action_error", "Action returned error", %{
                    "error" => "Always fails",
                    "port" => "error"
                  })
              }
            }
          ]
        },
        execution_graph: execution_graph,
        __runtime: %{
          "nodes" => %{},
          "env" => %{},
          "active_paths" => %{},
          "executed_nodes" => []
        },
        execution_data: %{
          "context_data" => %{
            "workflow" => %{},
            "node" => %{}
          },
          "active_paths" => %{},
          "active_nodes" => %{}
        }
      }

      # Resume should try retry again and return another suspension (since always_fail will fail again)
      result = GraphExecutor.resume_workflow(suspended_execution, %{})

      # Should return another suspension for the next retry attempt
      assert {:suspend, suspended_again_execution, suspension_data} = result
      assert suspended_again_execution.status == "suspended"
      assert suspension_data["attempt_number"] == 2
      assert suspension_data["max_attempts"] == 3
    end
  end
end
