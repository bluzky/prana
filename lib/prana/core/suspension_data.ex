defmodule Prana.Core.SuspensionData do
  @moduledoc """
  Typed suspension data structures for different suspension types.

  This module defines structured data types for various suspension scenarios,
  replacing the generic resume_token approach with typed, direct field access.
  """

  @type suspension_type :: :webhook | :interval | :schedule | :sub_workflow | atom()

  @type webhook_suspension_data :: %{
          resume_url: String.t(),
          webhook_id: String.t(),
          timeout_seconds: pos_integer() | nil,
          metadata: map()
        }

  @type interval_suspension_data :: %{
          duration_seconds: pos_integer(),
          started_at: DateTime.t(),
          resume_at: DateTime.t(),
          metadata: map()
        }

  @type schedule_suspension_data :: %{
          scheduled_at: DateTime.t(),
          timezone: String.t() | nil,
          cron_expression: String.t() | nil,
          metadata: map()
        }

  @type sub_workflow_suspension_data :: %{
          sub_workflow_execution_id: String.t(),
          sub_workflow_id: String.t(),
          execution_mode: :sync | :async | :fire_and_forget,
          started_at: DateTime.t(),
          metadata: map()
        }

  @type suspension_data ::
          webhook_suspension_data()
          | interval_suspension_data()
          | schedule_suspension_data()
          | sub_workflow_suspension_data()
          | map()

  @doc """
  Creates webhook suspension data.

  ## Parameters
  - `resume_url` - URL for webhook callbacks
  - `webhook_id` - Unique identifier for the webhook
  - `timeout_seconds` - Optional timeout in seconds
  - `metadata` - Additional metadata map

  ## Example

      iex> create_webhook_suspension("https://app.com/webhook/abc123", "webhook_1", 3600)
      %{
        resume_url: "https://app.com/webhook/abc123",
        webhook_id: "webhook_1", 
        timeout_seconds: 3600,
        metadata: %{}
      }
  """
  @spec create_webhook_suspension(String.t(), String.t(), pos_integer() | nil, map()) ::
          webhook_suspension_data()
  def create_webhook_suspension(resume_url, webhook_id, timeout_seconds \\ nil, metadata \\ %{}) do
    %{
      resume_url: resume_url,
      webhook_id: webhook_id,
      timeout_seconds: timeout_seconds,
      metadata: metadata
    }
  end

  @doc """
  Creates interval suspension data.

  ## Parameters
  - `duration_seconds` - Duration to wait in seconds
  - `started_at` - When the interval started (defaults to now)
  - `metadata` - Additional metadata map

  ## Example

      iex> create_interval_suspension(300)
      %{
        duration_seconds: 300,
        started_at: ~U[2024-01-01 12:00:00Z],
        resume_at: ~U[2024-01-01 12:05:00Z],
        metadata: %{}
      }
  """
  @spec create_interval_suspension(pos_integer(), DateTime.t(), map()) ::
          interval_suspension_data()
  def create_interval_suspension(duration_seconds, started_at \\ DateTime.utc_now(), metadata \\ %{}) do
    resume_at = DateTime.add(started_at, duration_seconds, :second)

    %{
      duration_seconds: duration_seconds,
      started_at: started_at,
      resume_at: resume_at,
      metadata: metadata
    }
  end

  @doc """
  Creates schedule suspension data.

  ## Parameters
  - `scheduled_at` - When to resume execution
  - `timezone` - Timezone for schedule (optional)
  - `cron_expression` - Cron expression for recurring schedules (optional)
  - `metadata` - Additional metadata map

  ## Example

      iex> scheduled_time = ~U[2024-01-01 18:00:00Z]
      iex> create_schedule_suspension(scheduled_time, "America/New_York")
      %{
        scheduled_at: ~U[2024-01-01 18:00:00Z],
        timezone: "America/New_York",
        cron_expression: nil,
        metadata: %{}
      }
  """
  @spec create_schedule_suspension(DateTime.t(), String.t() | nil, String.t() | nil, map()) ::
          schedule_suspension_data()
  def create_schedule_suspension(scheduled_at, timezone \\ nil, cron_expression \\ nil, metadata \\ %{}) do
    %{
      scheduled_at: scheduled_at,
      timezone: timezone,
      cron_expression: cron_expression,
      metadata: metadata
    }
  end

  @doc """
  Creates sub-workflow suspension data.

  ## Parameters
  - `sub_workflow_execution_id` - ID of the sub-workflow execution
  - `sub_workflow_id` - ID of the sub-workflow definition
  - `execution_mode` - How the sub-workflow is executed
  - `started_at` - When the sub-workflow started (defaults to now)
  - `metadata` - Additional metadata map

  ## Example

      iex> create_sub_workflow_suspension("exec_123", "workflow_456", :async)
      %{
        sub_workflow_execution_id: "exec_123",
        sub_workflow_id: "workflow_456",
        execution_mode: :async,
        started_at: ~U[2024-01-01 12:00:00Z],
        metadata: %{}
      }
  """
  @spec create_sub_workflow_suspension(String.t(), String.t(), atom(), DateTime.t(), map()) ::
          sub_workflow_suspension_data()
  def create_sub_workflow_suspension(
        sub_workflow_execution_id,
        sub_workflow_id,
        execution_mode,
        started_at \\ DateTime.utc_now(),
        metadata \\ %{}
      ) do
    %{
      sub_workflow_execution_id: sub_workflow_execution_id,
      sub_workflow_id: sub_workflow_id,
      execution_mode: execution_mode,
      started_at: started_at,
      metadata: metadata
    }
  end

  @doc """
  Validates suspension data for a given suspension type.

  ## Parameters
  - `suspension_type` - The type of suspension
  - `suspension_data` - The suspension data to validate

  ## Returns
  - `:ok` if valid
  - `{:error, reason}` if invalid

  ## Example

      iex> data = create_webhook_suspension("https://app.com/webhook", "webhook_1")
      iex> validate_suspension_data(:webhook, data)
      :ok

      iex> validate_suspension_data(:webhook, %{invalid: "data"})
      {:error, "Invalid webhook suspension data: missing resume_url"}
  """
  @spec validate_suspension_data(suspension_type(), suspension_data()) ::
          :ok | {:error, String.t()}
  def validate_suspension_data(:webhook, data) do
    required_fields = [:resume_url, :webhook_id]
    validate_required_fields(data, required_fields, "webhook")
  end

  def validate_suspension_data(:interval, data) do
    required_fields = [:duration_seconds, :started_at, :resume_at]
    validate_required_fields(data, required_fields, "interval")
  end

  def validate_suspension_data(:schedule, data) do
    required_fields = [:scheduled_at]
    validate_required_fields(data, required_fields, "schedule")
  end

  def validate_suspension_data(:sub_workflow, data) do
    required_fields = [:sub_workflow_execution_id, :sub_workflow_id, :execution_mode]
    validate_required_fields(data, required_fields, "sub_workflow")
  end

  def validate_suspension_data(_type, _data) do
    # Custom suspension types are not validated
    :ok
  end

  defp validate_required_fields(data, required_fields, type_name) do
    missing_fields =
      Enum.reject(required_fields, &Map.has_key?(data, &1))

    case missing_fields do
      [] ->
        :ok

      [field] ->
        {:error, "Invalid #{type_name} suspension data: missing #{field}"}

      fields ->
        fields_str = Enum.join(fields, ", ")
        {:error, "Invalid #{type_name} suspension data: missing #{fields_str}"}
    end
  end

  @doc """
  Extracts resume information from suspension data.

  Returns a standardized map with resume timing and metadata
  regardless of suspension type.

  ## Example

      iex> data = create_interval_suspension(300)
      iex> extract_resume_info(data)
      %{
        resume_at: ~U[2024-01-01 12:05:00Z],
        timeout_at: nil,
        resumable: true,
        metadata: %{}
      }
  """
  @spec extract_resume_info(suspension_data()) :: %{
          resume_at: DateTime.t() | nil,
          timeout_at: DateTime.t() | nil,
          resumable: boolean(),
          metadata: map()
        }
  def extract_resume_info(%{resume_at: resume_at, metadata: metadata}) do
    %{
      resume_at: resume_at,
      timeout_at: nil,
      resumable: true,
      metadata: metadata
    }
  end

  def extract_resume_info(%{scheduled_at: scheduled_at, metadata: metadata}) do
    %{
      resume_at: scheduled_at,
      timeout_at: nil,
      resumable: true,
      metadata: metadata
    }
  end

  def extract_resume_info(%{timeout_seconds: timeout_seconds, metadata: metadata}) when is_integer(timeout_seconds) do
    timeout_at = DateTime.add(DateTime.utc_now(), timeout_seconds, :second)

    %{
      resume_at: nil,
      timeout_at: timeout_at,
      resumable: true,
      metadata: metadata
    }
  end

  def extract_resume_info(%{metadata: metadata}) do
    %{
      resume_at: nil,
      timeout_at: nil,
      resumable: true,
      metadata: metadata
    }
  end

  def extract_resume_info(data) when is_map(data) do
    metadata = Map.get(data, :metadata, %{})

    %{
      resume_at: nil,
      timeout_at: nil,
      resumable: true,
      metadata: metadata
    }
  end
end
