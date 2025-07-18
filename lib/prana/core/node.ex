defmodule Prana.Node do
  @moduledoc """
  Represents an individual node in a workflow
  """

  @type t :: %__MODULE__{
          # id: String.t(),
          name: String.t(),
          key: String.t(),
          type: String.t(),
          params: map(),
          metadata: map()
        }

  defstruct [
    # :id,
    # key is unique identifier for the node accross workflow
    :key,
    :name,
    :type,
    :params,
    metadata: %{}
  ]

  @doc """
  Creates a new node with type format "<integration>.<action>"
  """
  def new(name, type, params \\ %{}, key \\ nil) do
    %__MODULE__{
      # id: generate_id(),
      key: key || generate_custom_id(name) || generate_id(),
      name: name,
      type: type,
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
      type: Map.get(data, "type") || Map.get(data, :type),
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
         :ok <- validate_type(node) do
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
    required_fields = [:key, :name, :type]

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

  defp validate_type(%__MODULE__{type: type}) do
    # Validate type format is "<integration>.<action>"
    case String.split(type, ".", parts: 2) do
      [integration, action] when byte_size(integration) > 0 and byte_size(action) > 0 ->
        :ok

      _ ->
        {:error, "Invalid type format. Expected '<integration>.<action>'"}
    end
  end
end
