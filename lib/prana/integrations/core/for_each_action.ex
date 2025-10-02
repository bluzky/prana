defmodule Prana.Integrations.Core.ForEachAction do
  @moduledoc """
  For Each Loop Action - Iterate over collections with single or batch processing

  Provides loop constructs for workflow execution with optimized iteration strategy.
  Processes collections item-by-item or in batches, with automatic loopback to continue iteration.

  ## Parameters
  - `collection` (required): Template expression that evaluates to an array/list
  - `mode` (required): Processing mode - "single" or "batch"
  - `batch_size` (required for batch mode): Number of items per batch (minimum: 1)

  ## Example Params JSON

  ### Single Item Processing
  ```json
  {
    "collection": "{{$input.users}}",
    "mode": "single"
  }
  ```

  ### Batch Processing
  ```json
  {
    "collection": "{{$input.orders}}",
    "mode": "batch",
    "batch_size": 10
  }
  ```

  ### Complex Collection
  ```json
  {
    "collection": "{{$nodes.data_fetch.output.items}}",
    "mode": "single"
  }
  ```

  ## Output Ports
  - `loop`: Current item/batch data for processing (continues loop)
  - `done`: Loop completed, no more items
  - `error`: Collection validation or processing errors

  ## Loop Behavior
  1. **First execution**: Evaluates collection, outputs first item/batch via "loop" port
  2. **Subsequent executions**: Outputs next item/batch via "loop" port
  3. **Completion**: When no more items remain, exits via "done" port

  ## Output Data
  - **Single mode**: Returns the individual item from the collection
  - **Batch mode**: Returns array of items in the current batch

  ## Context Storage
  The action maintains internal context for efficient iteration:
  - Original collection size and remaining items
  - Current loop and run indices
  - Batch processing state

  ## Performance
  Uses remaining_items approach to avoid expensive array slicing operations,
  making it efficient for large collections.
  """

  use Skema
  use Prana.Actions.SimpleAction

  alias Prana.Action
  alias Prana.Core.Error

  defschema ForEachSchema do
    field(:collection, :any, required: true)
    field(:mode, :string, required: true, in: ["single", "batch"])
    field(:batch_size, :integer, number: [min: 1])
  end

  def definition do
    %Action{
      name: "prana_core.for_each",
      display_name: "For Each",
      description: @moduledoc,
      type: :action,
      input_ports: ["main"],
      output_ports: ["loop", "done"]
    }
  end

  defp validate_params(input_map) do
    case Skema.cast_and_validate(input_map, ForEachSchema) do
      {:ok, validated_data} ->
        # Additional validation for batch mode
        case validated_data do
          %{mode: "batch"} ->
            if is_nil(validated_data.batch_size) do
              {:error,
               Error.new("validation_error", "batch_size is required for batch mode and must be >= 1", %{
                 "errors" => [%{field: :batch_size, message: "is required for batch mode and must be >= 1"}]
               })}
            else
              {:ok, validated_data}
            end

          _ ->
            {:ok, validated_data}
        end

      {:error, errors} ->
        {:error, format_errors(errors)}
    end
  end

  @impl true
  def execute(params, context) do
    # Use Skema validation
    case validate_params(params) do
      {:ok, validated_params} ->
        node_key = context["$execution"]["current_node_key"]
        loopback = context["$execution"]["loopback"]
        node_context = Nested.get(context, ["$nodes", node_key, "context"]) || %{}

        case {loopback, node_context} do
          {false, _} ->
            # First execution - start new loop
            start_new_loop(validated_params, context)

          {true, %{"remaining_items" => []}} ->
            {:ok, %{}, "done"}

          {true, %{"remaining_items" => _remaining}} ->
            continue_loop(validated_params, context, node_context)

          _ ->
            {:error, Error.new("invalid_loopback", "Loopback context is invalid or missing")}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  # Start new loop - evaluate collection and process first item/batch
  defp start_new_loop(validated_params, context) do
    # Collection is passed as validated parameter
    collection = validated_params.collection

    with :ok <- validate_collection(collection),
         {:ok, {item_or_batch, remaining_items}} <- get_next_item_or_batch(collection, validated_params) do
      node_context_updates = %{
        "item_count" => length(collection),
        "remaining_items" => remaining_items,
        "current_loop_index" => 0,
        "current_run_index" => Nested.get(context, ["$context", "run_index"]),
        "has_more_item" => not Enum.empty?(remaining_items)
      }

      # Return first item/batch with context updates
      {:ok, item_or_batch, "loop", %{"node_context" => node_context_updates}}
    else
      :no_more_items ->
        {:ok, %{}, "done"}

      error ->
        error
    end
  end

  # Continue existing loop - process next item/batch from remaining items
  defp continue_loop(validated_params, _context, node_context) do
    %{
      "remaining_items" => remaining_items,
      "current_loop_index" => current_loop_index,
      "current_run_index" => current_run_index
    } = node_context

    {:ok, {item_or_batch, new_remaining}} = get_next_item_or_batch(remaining_items, validated_params)

    node_context_updates = %{
      node_context
      | "remaining_items" => new_remaining,
        "current_loop_index" => current_loop_index + 1,
        "current_run_index" => current_run_index + 1,
        "has_more_item" => not Enum.empty?(new_remaining)
    }

    {:ok, item_or_batch, "loop", %{"node_context" => node_context_updates}}
  end

  # Format Skema validation errors
  defp format_errors(%{errors: errors}) when is_map(errors) do
    formatted_errors =
      Enum.map(errors, fn {field, messages} ->
        message = if is_list(messages), do: Enum.join(messages, ", "), else: messages

        %{
          field: field,
          message: message
        }
      end)

    Error.new("validation_error", "Parameter validation failed", %{
      "errors" => formatted_errors
    })
  end

  # Validate that collection is an enumerable list/array
  defp validate_collection(collection) when is_list(collection), do: :ok
  defp validate_collection(collection) when is_map(collection) and map_size(collection) == 0, do: :ok

  defp validate_collection(collection) do
    {:error,
     Error.new("invalid_collection_type", "Collection must be a list/array", %{
       "collection" => inspect(collection, limit: 50)
     })}
  end

  defp get_next_item_or_batch([], _), do: :no_more_items

  defp get_next_item_or_batch(remaining_items, %{mode: "single"}) do
    [first | rest] = remaining_items
    {:ok, {first, rest}}
  end

  defp get_next_item_or_batch(remaining_items, %{mode: "batch", batch_size: batch_size}) do
    batch = Enum.take(remaining_items, batch_size)
    remaining = Enum.drop(remaining_items, batch_size)
    {:ok, {batch, remaining}}
  end
end
