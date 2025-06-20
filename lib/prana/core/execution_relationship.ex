defmodule Prana.ExecutionRelationship do
  @moduledoc """
  Tracks relationships between parent and child executions for sub-workflows
  """
  
  @type relationship_type :: :sync | :async | :fire_and_forget
  
  @type t :: %__MODULE__{
    id: String.t(),
    parent_execution_id: String.t(),
    child_execution_id: String.t(),
    relationship_type: relationship_type(),
    triggered_by_node_id: String.t(),
    wait_condition: :all_complete | :all_success | :any_complete | :custom,
    custom_condition: String.t() | nil,
    created_at: DateTime.t(),
    metadata: map()
  }

  defstruct [
    :id, :parent_execution_id, :child_execution_id, :relationship_type,
    :triggered_by_node_id, :wait_condition, :custom_condition,
    :created_at, metadata: %{}
  ]

  @doc """
  Creates a new execution relationship
  """
  def new(parent_execution_id, child_execution_id, relationship_type, triggered_by_node_id) do
    %__MODULE__{
      id: generate_id(),
      parent_execution_id: parent_execution_id,
      child_execution_id: child_execution_id,
      relationship_type: relationship_type,
      triggered_by_node_id: triggered_by_node_id,
      wait_condition: :all_complete,
      custom_condition: nil,
      created_at: DateTime.utc_now(),
      metadata: %{}
    }
  end

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode64() |> binary_part(0, 16)
  end
end
