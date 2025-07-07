defmodule Prana.Node do
  @moduledoc """
  Represents an individual node in a workflow
  """

  @type t :: %__MODULE__{
          id: String.t(),
          custom_id: String.t(),
          name: String.t(),
          description: String.t() | nil,
          integration_name: String.t(),
          action_name: String.t(),
          params: map(),
          output_ports: [String.t()],
          input_ports: [String.t()],
          error_handling: Prana.ErrorHandling.t(),
          retry_policy: Prana.RetryPolicy.t() | nil,
          timeout_seconds: integer() | nil,
          metadata: map()
        }

  defstruct [
    :id,
    :custom_id,
    :name,
    :description,
    :integration_name,
    :action_name,
    :params,
    :output_ports,
    :input_ports,
    :error_handling,
    :retry_policy,
    :timeout_seconds,
    metadata: %{}
  ]

  @doc """
  Creates a new node
  """
  def new(name, integration_name, action_name, params \\ %{}, custom_id \\ nil) do
    %__MODULE__{
      id: generate_id(),
      custom_id: custom_id || generate_custom_id(name),
      name: name,
      integration_name: integration_name,
      action_name: action_name,
      params: params,
      output_ports: [],
      input_ports: [],
      error_handling: %Prana.ErrorHandling{},
      retry_policy: nil,
      timeout_seconds: nil,
      metadata: %{}
    }
  end

  @doc """
  Loads a node from a map
  """
  def from_map(data) when is_map(data) do
    %__MODULE__{
      id: Map.get(data, "id") || Map.get(data, :id) || generate_id(),
      custom_id: Map.get(data, "custom_id") || Map.get(data, :custom_id),
      name: Map.get(data, "name") || Map.get(data, :name),
      description: Map.get(data, "description") || Map.get(data, :description),
      integration_name: Map.get(data, "integration_name") || Map.get(data, :integration_name),
      action_name: Map.get(data, "action_name") || Map.get(data, :action_name),
      params: Map.get(data, "params") || Map.get(data, :params) || Map.get(data, "input_map") || Map.get(data, :input_map) || %{},
      output_ports: Map.get(data, "output_ports") || Map.get(data, :output_ports) || [],
      input_ports: Map.get(data, "input_ports") || Map.get(data, :input_ports) || [],
      error_handling: parse_error_handling(Map.get(data, "error_handling") || Map.get(data, :error_handling)),
      retry_policy: parse_retry_policy(Map.get(data, "retry_policy") || Map.get(data, :retry_policy)),
      timeout_seconds: Map.get(data, "timeout_seconds") || Map.get(data, :timeout_seconds),
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
    16 |> :crypto.strong_rand_bytes() |> Base.encode64() |> binary_part(0, 16)
  end

  defp generate_custom_id(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_]/, "_")
    |> String.replace(~r/_+/, "_")
    |> String.trim("_")
  end


  defp parse_error_handling(nil), do: %Prana.ErrorHandling{}
  defp parse_error_handling(data) when is_map(data), do: struct(Prana.ErrorHandling, data)
  defp parse_error_handling(_), do: %Prana.ErrorHandling{}

  defp parse_retry_policy(nil), do: nil
  defp parse_retry_policy(data) when is_map(data), do: struct(Prana.RetryPolicy, data)
  defp parse_retry_policy(_), do: nil

  defp validate_required_fields(%__MODULE__{} = node) do
    required_fields = [:id, :name, :integration_name, :action_name]

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
