defmodule Prana.Behaviour.Action do
  @moduledoc """
  Behavior for defining workflow actions with prepare/execute/resume lifecycle.

  This behavior supports the complete action lifecycle:
  - `prepare/2` - Pre-execution setup with access to execution context
  - `execute/1` - Main action execution with input data
  - `resume/2` - Resume suspended actions with external input

  ## Action Lifecycle

  1. **Preparation Phase**: Called once during workflow preparation
     - Access to full execution context for dynamic configuration
     - Returns preparation data stored in context for later use
     - Can validate configuration and setup external resources

  2. **Execution Phase**: Called when node is ready to execute
     - Receives input data from previous nodes (includes preparation data if needed)
     - Can return success, suspension, or error

  3. **Resume Phase**: Called when suspended action receives external input
     - Receives suspension data and resume input
     - Completes the action execution
     - Returns final success or error

  ## Suspension Types

  Actions can suspend execution and wait for external events:
  - `:webhook` - Wait for HTTP webhook callback
  - `:interval` - Wait for time interval to elapse  
  - `:schedule` - Wait for scheduled time
  - `:sub_workflow` - Wait for sub-workflow completion
  - Custom suspension types supported

  ## Example Implementation

      defmodule MyApp.HttpAction do
        @behaviour Prana.Behaviour.Action

        def prepare(action_config, execution_context) do
          # Validate configuration and setup
          api_key = execution_context.variables["api_key"]
          
          if api_key do
            {:ok, %{api_key: api_key, endpoint: action_config["endpoint"]}}
          else
            {:error, "Missing API key"}
          end
        end

        def execute(input_data) do
          # Make HTTP request with configuration from input_data
          case make_request(input_data["endpoint"], input_data, input_data["api_key"]) do
            {:ok, response} -> {:ok, response}
            {:error, reason} -> {:error, reason}
          end
        end

        def resume(_suspend_data, _resume_input) do
          # This action doesn't support suspension
          {:error, "Resume not supported"}
        end
      end

  ## Suspension Example

      def execute(input_data) do
        webhook_url = input_data["webhook_url"]
        
        # Initiate async operation that will callback to webhook
        {:ok, request_id} = start_async_operation(input_data, webhook_url)
        
        # Suspend with webhook data
        suspend_data = %{
          request_id: request_id,
          webhook_url: webhook_url,
          started_at: DateTime.utc_now()
        }
        
        {:suspend, :webhook, suspend_data}
      end

      def resume(suspend_data, resume_input) do
        # Process webhook callback
        case resume_input do
          %{"status" => "success", "result" => result} ->
            {:ok, result}
          %{"status" => "error", "error" => error} ->
            {:error, error}
        end
      end
  """

  alias Prana.Core.ExecutionContext

  @type suspension_type :: :webhook | :interval | :schedule | :sub_workflow | atom()
  @type suspend_data :: term()
  @type preparation_data :: map()
  @type input_data :: map() 
  @type output_data :: term()
  @type resume_input :: map()

  @doc """
  Prepare action for execution during workflow initialization.

  Called once during workflow preparation phase before any nodes execute.
  Simple initialization phase with the node definition.

  ## Parameters
  - `node` - The node struct containing action configuration

  ## Returns
  - `{:ok, preparation_data}` - Preparation successful, data stored in execution
  - `{:error, reason}` - Preparation failed, workflow cannot start

  ## Examples

      def prepare(_node) do
        {:ok, %{initialized_at: DateTime.utc_now()}}
      end
  """
  @callback prepare(node :: Prana.Node.t()) ::
              {:ok, preparation_data()} | {:error, reason :: term()}

  @doc """
  Execute the action with input data.

  Called when the node is ready to execute during workflow execution.
  Receives processed input data from previous nodes and expressions.

  ## Parameters
  - `input_data` - Processed input data from previous nodes and expressions

  ## Returns
  - `{:ok, output_data}` - Action completed successfully
  - `{:suspend, suspension_type, suspend_data}` - Action suspended, waiting for external event
  - `{:error, reason}` - Action failed

  ## Examples

      def execute(input_data) do
        case make_api_call(input_data["endpoint"], input_data) do
          {:ok, response} -> {:ok, response}
          {:error, reason} -> {:error, reason}
        end
      end

      # Suspension example
      def execute(input_data) do
        webhook_url = input_data["webhook_url"]
        {:ok, request_id} = start_async_operation(input_data, webhook_url)
        
        suspend_data = %{request_id: request_id, webhook_url: webhook_url}
        {:suspend, :webhook, suspend_data}
      end
  """
  @callback execute(input_data()) ::
              {:ok, output_data()} | {:suspend, suspension_type(), suspend_data()} | {:error, reason :: term()}

  @doc """
  Resume suspended action with external input.

  Called when a suspended action receives external input (e.g., webhook callback,
  timer expiration, sub-workflow completion). Processes the resume input and
  completes the action execution.

  ## Parameters
  - `suspend_data` - Data returned from execute/2 when action suspended
  - `resume_input` - External input data (webhook payload, timer data, etc.)

  ## Returns
  - `{:ok, output_data}` - Action completed successfully
  - `{:error, reason}` - Action failed during resume

  ## Examples

      def resume(suspend_data, resume_input) do
        case resume_input do
          %{"status" => "success", "data" => data} ->
            {:ok, data}
          %{"status" => "error", "error" => error} ->
            {:error, error}
          _ ->
            {:error, "Invalid resume input"}
        end
      end
  """
  @callback resume(suspend_data(), resume_input()) ::
              {:ok, output_data()} | {:error, reason :: term()}

  @doc """
  Returns true if this action supports suspension/resume operations.
  
  Default implementation returns false. Override to return true for actions
  that implement suspension/resume functionality.
  """
  @callback suspendable?() :: boolean()

  @optional_callbacks [suspendable?: 0]

  defmacro __using__(_opts) do
    quote do
      @behaviour Prana.Behaviour.Action

      def suspendable?, do: false

      defoverridable suspendable?: 0
    end
  end
end