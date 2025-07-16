defmodule Prana.Node do
  @moduledoc """
  Represents an individual node in a workflow
  """

  @type t :: %__MODULE__{
          # id: String.t(),
          name: String.t(),
          key: String.t(),
          integration_name: String.t(),
          action_name: String.t(),
          params: map(),
          metadata: map()
        }

  defstruct [
    # :id,
    # key is unique identifier for the node accross workflow
    :key,
    :name,
    :integration_name,
    :action_name,
    :params,
    metadata: %{}
  ]

  @doc """
  Creates a new node
  """
  def new(name, integration_name, action_name, params \\ %{}, key \\ nil) do
    %__MODULE__{
      # id: generate_id(),
      key: key || generate_custom_id(name) || generate_id(),
      name: name,
      integration_name: integration_name,
      action_name: action_name,
      params: params,
      metadata: %{}
    }
  end

  @doc """
  Loads a node from a map
  """
  def from_map(data) when is_map(data) do
    %__MODULE__{
      name: Map.get(data, "name") || Map.get(data, :name),
      key: Map.get(data, "key") || Map.get(data, :key),
      integration_name: Map.get(data, "integration_name") || Map.get(data, :integration_name),
      action_name: Map.get(data, "action_name") || Map.get(data, :action_name),
      params:
        Map.get(data, "params") || Map.get(data, :params) || Map.get(data, "input_map") || Map.get(data, :input_map) ||
          %{},
      metadata: Map.get(data, "metadata") || Map.get(data, :metadata) || %{}
    }
  end

  @doc """
  Validates a node
  """
  def valid?(%__MODULE__{} = node) do
    with :ok <- validate_required_fields(node),
         :ok <- validate_integration_action(node) do
      :ok
    else
      {:error, _reason} = error -> error
    end
  end

  # Private functions

  defp generate_id do
    UUID.uuid4()
  end

  defp generate_custom_id(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_]/, "_")
    |> String.replace(~r/_+/, "_")
    |> String.trim("_")
  end

  defp validate_required_fields(%__MODULE__{} = node) do
    required_fields = [:key, :name, :integration_name, :action_name]

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
