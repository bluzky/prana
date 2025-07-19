defmodule Prana.Webhook do
  @moduledoc """
  Webhook utility functions for generating IDs, building URLs, and validation.

  This module provides pure utility functions for webhook operations without
  any centralized state management. Applications handle persistence and routing.

  ## Webhook Lifecycle States

  Resume webhooks follow a strict lifecycle:

  - `"pending"` - Created at execution start, not yet active
  - `:active` - Wait node activated, ready to receive requests
  - `:consumed` - Successfully used to resume execution (one-time use)
  - `:expired` - Timed out or execution completed without use

  ## Usage

      # Generate unique resume webhook ID
      resume_id = Prana.Webhook.generate_resume_id("exec_123", "wait_approval")
      # => "webhook_exec_123_wait_approval_AbC123"

      # Extract parts from resume ID
      {:ok, parts} = Prana.Webhook.extract_resume_id_parts(resume_id)
      # => {:ok, %{execution_id: "exec_123", node_id: "wait_approval"}}

      # Build full webhook URL
      url = Prana.Webhook.build_webhook_url("https://myapp.com", :resume, resume_id)
      # => "https://myapp.com/webhook/workflow/resume/webhook_exec_123_wait_approval_AbC123"

      # Validate webhook state
      :ok = Prana.Webhook.validate_webhook_state(:active)
  """

  @type webhook_type :: :trigger | :resume
  @type webhook_state :: :pending | :active | :consumed | :expired
  @type webhook_data :: %{
          token: String.t(),
          execution_id: String.t(),
          node_id: String.t(),
          status: webhook_state(),
          created_at: DateTime.t(),
          expires_at: DateTime.t() | nil,
          webhook_config: map()
        }

  @doc """
  Generate a unique resume webhook ID.

  Creates a unique identifier following the pattern:
  `{execution_id}_{unique_token}`

  ## Parameters

  - `execution_id` - The workflow execution ID

  ## Examples

      iex> id = Prana.Webhook.generate_resume_id("exec123")
      iex> String.starts_with?(id, "exec123_")
      true

      iex> id = Prana.Webhook.generate_resume_id("execWorkflowTest")
      iex> String.starts_with?(id, "execWorkflowTest_")
      true
  """
  @spec generate_resume_id(String.t()) :: String.t()
  def generate_resume_id(execution_id) when is_binary(execution_id) do
    unique_token = 8 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    "#{execution_id}_#{unique_token}"
  end

  @doc """
  Extract execution_id and token from a resume webhook ID.

  Parses a resume webhook ID back into its component parts.

  ## Parameters

  - `resume_id` - The resume webhook ID to parse

  ## Returns

  - `{:ok, %{execution_id: string, token: string}}` - Successfully parsed
  - `{:error, reason}` - Invalid format

  ## Examples

      iex> Prana.Webhook.extract_resume_id_parts("exec123_AbC123def")
      {:ok, %{execution_id: "exec123", token: "AbC123def"}}

      iex> Prana.Webhook.extract_resume_id_parts("execWorkflowTest_XyZ789")
      {:ok, %{execution_id: "execWorkflowTest", token: "XyZ789"}}

      iex> Prana.Webhook.extract_resume_id_parts("invalid@format")
      {:error, "Invalid resume_id format"}
  """
  @spec extract_resume_id_parts(String.t()) ::
          {:ok, %{execution_id: String.t(), token: String.t()}} | {:error, String.t()}
  def extract_resume_id_parts(resume_id) when is_binary(resume_id) do
    # The resume ID format is: {execution_id}_{unique_token}

    case String.split(resume_id, "_", parts: 2) do
      [execution_id, token] ->
        # Validate that execution_id is not empty and token looks like base64 with reasonable length
        if String.trim(execution_id) == "" do
          {:error, "Invalid resume_id format"}
        else
          {:ok, %{execution_id: execution_id, token: token}}
        end

      _ ->
        {:error, "Invalid resume_id format"}
    end
  end

  @doc """
  Build a full webhook URL.

  Constructs complete webhook URLs for use in expressions and notifications.

  ## Parameters

  - `base_url` - The base application URL (e.g., "https://myapp.com")
  - `type` - The webhook type (`:trigger` or `:resume`)
  - `id` - The workflow_id (for trigger) or resume_id (for resume)

  ## Examples

      iex> Prana.Webhook.build_webhook_url("https://myapp.com", :trigger, "user_signup")
      "https://myapp.com/webhook/workflow/trigger/user_signup"

      iex> Prana.Webhook.build_webhook_url("https://myapp.com", :resume, "exec123_AbC123def")
      "https://myapp.com/webhook/workflow/resume/exec123_AbC123def"
  """
  @spec build_webhook_url(String.t(), webhook_type(), String.t()) :: String.t()
  def build_webhook_url(base_url, type, id) when is_binary(base_url) and is_binary(id) do
    base_url = String.trim_trailing(base_url, "/")

    case type do
      :trigger -> "#{base_url}/webhook/workflow/trigger/#{id}"
      :resume -> "#{base_url}/webhook/workflow/resume/#{id}"
    end
  end

  @doc """
  Validate a webhook lifecycle state.

  Ensures webhook states are valid according to the defined lifecycle.

  ## Valid States

  - `"pending"` - Created at execution start, not yet active
  - `:active` - Wait node activated, ready to receive requests
  - `:consumed` - Successfully used to resume execution (one-time use)
  - `:expired` - Timed out or execution completed without use

  ## Parameters

  - `state` - The webhook state to validate

  ## Examples

      iex> Prana.Webhook.validate_webhook_state(:active)
      :ok

      iex> Prana.Webhook.validate_webhook_state(:invalid)
      {:error, "Invalid webhook state: :invalid"}
  """
  @spec validate_webhook_state(any()) :: :ok | {:error, String.t()}
  def validate_webhook_state(state) when state in ["pending", :active, :consumed, :expired] do
    :ok
  end

  def validate_webhook_state(nil) do
    {:error, "Webhook state cannot be nil"}
  end

  def validate_webhook_state(state) when not is_atom(state) do
    {:error, "Webhook state must be an atom"}
  end

  def validate_webhook_state(state) do
    {:error, "Invalid webhook state: #{inspect(state)}"}
  end

  @doc """
  Create webhook registration data structure.

  Helper function to create a standardized webhook data structure for
  application persistence.

  ## Parameters

  - `token` - The unique webhook token (extracted from resume_id)
  - `execution_id` - The workflow execution ID
  - `node_id` - The wait node ID
  - `config` - Additional webhook configuration (optional)

  ## Examples

      iex> data = Prana.Webhook.create_webhook_data(
      ...>   "AbC123def",
      ...>   "exec_123",
      ...>   "wait_approval",
      ...>   %{timeout_hours: 24}
      ...> )
      iex> data.token
      "AbC123def"
      iex> data.status
      "pending"
  """
  @spec create_webhook_data(String.t(), String.t(), String.t(), map()) :: webhook_data()
  def create_webhook_data(token, execution_id, node_id, config \\ %{})
      when is_binary(token) and is_binary(execution_id) and is_binary(node_id) and is_map(config) do
    %{
      token: token,
      execution_id: execution_id,
      node_id: node_id,
      status: "pending",
      created_at: DateTime.utc_now(),
      expires_at: nil,
      webhook_config: config
    }
  end

  @doc """
  Validate webhook state transition.

  Ensures webhook state transitions follow the valid lifecycle flow.

  Valid transitions:
  - `"pending"` → `:active`
  - `"pending"` → `:expired`
  - `:active` → `:consumed`
  - `:active` → `:expired`

  ## Parameters

  - `from_state` - Current webhook state
  - `to_state` - Desired new state

  ## Examples

      iex> Prana.Webhook.validate_state_transition("pending", :active)
      :ok

      iex> Prana.Webhook.validate_state_transition(:consumed, :active)
      {:error, "Invalid state transition from :consumed to :active"}
  """
  @spec validate_state_transition(webhook_state(), webhook_state()) :: :ok | {:error, String.t()}
  def validate_state_transition(from_state, to_state) do
    case {from_state, to_state} do
      {"pending", :active} -> :ok
      {"pending", :expired} -> :ok
      {:active, :consumed} -> :ok
      {:active, :expired} -> :ok
      # Allow same state (idempotent)
      {same, same} -> :ok
      _ -> {:error, "Invalid state transition from #{inspect(from_state)} to #{inspect(to_state)}"}
    end
  end
end
