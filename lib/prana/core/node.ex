defmodule Prana.Node do
  @moduledoc """
  Represents an individual node in a workflow
  """
  
  @type node_type :: :trigger | :action | :logic | :wait | :output
  @type t :: %__MODULE__{
    id: String.t(),
    name: String.t(),
    description: String.t() | nil,
    type: node_type(),
    integration_name: String.t(),
    action_name: String.t(),
    input_map: map(),
    output_ports: [String.t()],
    input_ports: [String.t()],
    position: Prana.Position.t(),
    error_handling: Prana.ErrorHandling.t(),
    retry_policy: Prana.RetryPolicy.t() | nil,
    timeout_seconds: integer() | nil,
    enabled: boolean(),
    metadata: map()
  }

  defstruct [
    :id, :name, :description, :type, :integration_name, :action_name,
    :input_map, :output_ports, :input_ports, :position, :error_handling,
    :retry_policy, :timeout_seconds, enabled: true, metadata: %{}
  ]

  @doc """
  Creates a new node
  """
  def new(name, type, integration_name, action_name, input_map \\ %{}) do
    %__MODULE__{
      id: generate_id(),
      name: name,
      type: type,
      integration_name: integration_name,
      action_name: action_name,
      input_map: input_map,
      output_ports: [],
      input_ports: [],
      position: %Prana.Position{x: 0.0, y: 0.0},
      error_handling: %Prana.ErrorHandling{},
      retry_policy: nil,
      timeout_seconds: nil,
      enabled: true,
      metadata: %{}
    }
  end

  @doc """
  Validates a node
  """
  def valid?(%__MODULE__{} = node) do
    with :ok <- validate_required_fields(node),
         :ok <- validate_type(node.type),
         :ok <- validate_integration_action(node) do
      :ok
    else
      {:error, _reason} = error -> error
    end
  end

  # Private functions

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode64() |> binary_part(0, 16)
  end

  defp validate_required_fields(%__MODULE__{} = node) do
    required_fields = [:id, :name, :type, :integration_name, :action_name]
    
    missing_fields = 
      Enum.reject(required_fields, fn field ->
        value = Map.get(node, field)
        value && value != ""
      end)

    if Enum.empty?(missing_fields) do
      :ok
    else
      {:error, "Missing required fields: #{inspect(missing_fields)}"}
    end
  end

  defp validate_type(type) when type in [:trigger, :action, :logic, :wait, :output], do: :ok
  defp validate_type(type), do: {:error, "Invalid node type: #{inspect(type)}"}

  defp validate_integration_action(%__MODULE__{integration_name: integration, action_name: action}) do
    # This would check with the integration registry in a real implementation
    # For now, just validate they're non-empty strings
    if is_binary(integration) && is_binary(action) && 
       String.length(integration) > 0 && String.length(action) > 0 do
      :ok
    else
      {:error, "Invalid integration or action name"}
    end
  end
end
