defmodule Prana.Connection do
  @moduledoc """
  Represents a connection between two nodes
  """

  @type t :: %__MODULE__{
          from: String.t(),
          from_port: String.t(),
          to: String.t(),
          to_port: String.t(),
          metadata: map()
        }

  defstruct [
    :from,
    :from_port,
    :to,
    :to_port,
    metadata: %{}
  ]

  @doc """
  Creates a new connection
  """
  def new(from, from_port, to, to_port \\ "input") do
    %__MODULE__{
      from: from,
      from_port: from_port,
      to: to,
      to_port: to_port,
      metadata: %{}
    }
  end

  @doc """
  Loads a connection from a map
  """
  def from_map(data) when is_map(data) do
    %__MODULE__{
      from: Map.get(data, "from") || Map.get(data, :from),
      from_port: Map.get(data, "from_port") || Map.get(data, :from_port),
      to: Map.get(data, "to") || Map.get(data, :to),
      to_port: Map.get(data, "to_port") || Map.get(data, :to_port) || "input",
      metadata: Map.get(data, "metadata") || Map.get(data, :metadata) || %{}
    }
  end

  @doc """
  Validates a connection
  """
  def valid?(%__MODULE__{} = connection) do
    required_fields = [:from, :from_port, :to, :to_port]

    missing_fields =
      Enum.reject(required_fields, fn field ->
        value = Map.get(connection, field)
        value && value != ""
      end)

    if Enum.empty?(missing_fields) do
      :ok
    else
      {:error, "Missing required connection fields: #{inspect(missing_fields)}"}
    end
  end

end
