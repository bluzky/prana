defmodule Prana.WebhookTest do
  use ExUnit.Case

  alias Prana.Webhook

  doctest Prana.Webhook

  describe "generate_resume_id/1" do
    test "generates unique resume ID with correct format" do
      execution_id = "exec123"

      resume_id = Webhook.generate_resume_id(execution_id)

      assert String.starts_with?(resume_id, "#{execution_id}_")
      assert String.length(resume_id) > String.length("#{execution_id}_")
    end

    test "generates different IDs for same inputs" do
      execution_id = "exec456"

      id1 = Webhook.generate_resume_id(execution_id)
      id2 = Webhook.generate_resume_id(execution_id)

      assert id1 != id2
      assert String.starts_with?(id1, "#{execution_id}_")
      assert String.starts_with?(id2, "#{execution_id}_")
    end

    test "handles alphanumeric execution ID" do
      execution_id = "execAbc123"

      resume_id = Webhook.generate_resume_id(execution_id)

      assert String.starts_with?(resume_id, "#{execution_id}_")
    end
  end

  describe "extract_resume_id_parts/1" do
    test "extracts parts from valid resume ID" do
      resume_id = "exec123_AbC123def"

      assert {:ok, parts} = Webhook.extract_resume_id_parts(resume_id)
      assert parts.execution_id == "exec123"
      assert parts.token == "AbC123def"
    end

    test "extracts parts from generated resume ID" do
      execution_id = "exec456"

      resume_id = Webhook.generate_resume_id(execution_id)

      assert {:ok, parts} = Webhook.extract_resume_id_parts(resume_id)
      assert parts.execution_id == execution_id
      assert String.match?(parts.token, ~r/^[A-Za-z0-9\-_]+$/)
    end

    test "handles alphanumeric execution ID" do
      resume_id = "execAbc123_XyZ789"

      assert {:ok, parts} = Webhook.extract_resume_id_parts(resume_id)
      assert parts.execution_id == "execAbc123"
      assert parts.token == "XyZ789"
    end

    test "returns error for invalid format" do
      assert {:error, "Invalid resume_id format"} = Webhook.extract_resume_id_parts("invalid@format")
      assert {:error, "Invalid resume_id format"} = Webhook.extract_resume_id_parts("onlyonepart")
      assert {:error, "Invalid resume_id format"} = Webhook.extract_resume_id_parts("")
    end

    test "returns error for empty execution_id" do
      assert {:error, "Invalid resume_id format"} = Webhook.extract_resume_id_parts("_abc123")
    end

    test "handles any token format" do
      assert {:ok, parts} = Webhook.extract_resume_id_parts("exec123_anytoken123")
      assert parts.execution_id == "exec123"
      assert parts.token == "anytoken123"
    end
  end

  describe "build_webhook_url/3" do
    test "builds trigger webhook URL" do
      base_url = "https://myapp.com"
      workflow_id = "user_signup"

      url = Webhook.build_webhook_url(base_url, :trigger, workflow_id)

      assert url == "https://myapp.com/webhook/workflow/trigger/user_signup"
    end

    test "builds resume webhook URL" do
      base_url = "https://myapp.com"
      resume_id = "exec123_AbC123def"

      url = Webhook.build_webhook_url(base_url, :resume, resume_id)

      assert url == "https://myapp.com/webhook/workflow/resume/exec123_AbC123def"
    end

    test "handles base URL with trailing slash" do
      base_url = "https://myapp.com/"
      workflow_id = "user_signup"

      url = Webhook.build_webhook_url(base_url, :trigger, workflow_id)

      assert url == "https://myapp.com/webhook/workflow/trigger/user_signup"
    end

    test "handles base URL without protocol" do
      base_url = "myapp.com"
      workflow_id = "user_signup"

      url = Webhook.build_webhook_url(base_url, :trigger, workflow_id)

      assert url == "myapp.com/webhook/workflow/trigger/user_signup"
    end

    test "handles IDs with special characters" do
      base_url = "https://myapp.com"
      workflow_id = "user-signup_v2"

      url = Webhook.build_webhook_url(base_url, :trigger, workflow_id)

      assert url == "https://myapp.com/webhook/workflow/trigger/user-signup_v2"
    end
  end

  describe "validate_webhook_state/1" do
    test "validates valid states" do
      assert :ok = Webhook.validate_webhook_state(:pending)
      assert :ok = Webhook.validate_webhook_state(:active)
      assert :ok = Webhook.validate_webhook_state(:consumed)
      assert :ok = Webhook.validate_webhook_state(:expired)
    end

    test "returns error for invalid states" do
      assert {:error, "Invalid webhook state: :invalid"} = Webhook.validate_webhook_state(:invalid)
      assert {:error, "Invalid webhook state: :unknown"} = Webhook.validate_webhook_state(:unknown)
    end

    test "returns error for nil state" do
      assert {:error, "Webhook state cannot be nil"} = Webhook.validate_webhook_state(nil)
    end

    test "returns error for non-atom states" do
      assert {:error, "Webhook state must be an atom"} = Webhook.validate_webhook_state("active")
      assert {:error, "Webhook state must be an atom"} = Webhook.validate_webhook_state(123)
      assert {:error, "Webhook state must be an atom"} = Webhook.validate_webhook_state(%{})
    end
  end

  describe "create_webhook_data/4" do
    test "creates webhook data with all required fields" do
      token = "AbC123def"
      execution_id = "exec_123"
      node_id = "wait_approval"
      config = %{timeout_hours: 24}

      data = Webhook.create_webhook_data(token, execution_id, node_id, config)

      assert data.token == token
      assert data.execution_id == execution_id
      assert data.node_id == node_id
      assert data.status == :pending
      assert %DateTime{} = data.created_at
      assert data.expires_at == nil
      assert data.webhook_config == config
    end

    test "creates webhook data with default empty config" do
      token = "XyZ789"
      execution_id = "exec_456"
      node_id = "wait_payment"

      data = Webhook.create_webhook_data(token, execution_id, node_id)

      assert data.token == token
      assert data.execution_id == execution_id
      assert data.node_id == node_id
      assert data.status == :pending
      assert %DateTime{} = data.created_at
      assert data.expires_at == nil
      assert data.webhook_config == %{}
    end

    test "sets created_at to current time" do
      before = DateTime.utc_now()

      data = Webhook.create_webhook_data("testtoken", "exec_test", "node_test")

      after_time = DateTime.utc_now()

      assert DateTime.compare(data.created_at, before) in [:gt, :eq]
      assert DateTime.compare(data.created_at, after_time) in [:lt, :eq]
    end
  end

  describe "validate_state_transition/2" do
    test "validates valid transitions" do
      assert :ok = Webhook.validate_state_transition(:pending, :active)
      assert :ok = Webhook.validate_state_transition(:pending, :expired)
      assert :ok = Webhook.validate_state_transition(:active, :consumed)
      assert :ok = Webhook.validate_state_transition(:active, :expired)
    end

    test "allows same state transitions (idempotent)" do
      assert :ok = Webhook.validate_state_transition(:pending, :pending)
      assert :ok = Webhook.validate_state_transition(:active, :active)
      assert :ok = Webhook.validate_state_transition(:consumed, :consumed)
      assert :ok = Webhook.validate_state_transition(:expired, :expired)
    end

    test "returns error for invalid transitions" do
      # Cannot go backwards
      assert {:error, "Invalid state transition from :active to :pending"} =
               Webhook.validate_state_transition(:active, :pending)

      assert {:error, "Invalid state transition from :consumed to :pending"} =
               Webhook.validate_state_transition(:consumed, :pending)

      assert {:error, "Invalid state transition from :consumed to :active"} =
               Webhook.validate_state_transition(:consumed, :active)

      assert {:error, "Invalid state transition from :expired to :pending"} =
               Webhook.validate_state_transition(:expired, :pending)

      assert {:error, "Invalid state transition from :expired to :active"} =
               Webhook.validate_state_transition(:expired, :active)

      assert {:error, "Invalid state transition from :expired to :consumed"} =
               Webhook.validate_state_transition(:expired, :consumed)
    end
  end

  describe "integration tests" do
    test "end-to-end workflow with generated resume ID" do
      # Step 1: Generate resume ID at execution start
      execution_id = "execWorkflowTest"
      node_id = "waitUserApproval"

      resume_id = Webhook.generate_resume_id(execution_id)

      # Step 2: Extract token from resume ID
      {:ok, parts} = Webhook.extract_resume_id_parts(resume_id)
      assert parts.execution_id == execution_id
      token = parts.token

      # Step 3: Create webhook data for persistence
      webhook_data = Webhook.create_webhook_data(token, execution_id, node_id, %{timeout_hours: 48})

      assert webhook_data.status == :pending
      assert webhook_data.execution_id == execution_id
      assert webhook_data.node_id == node_id
      assert webhook_data.token == token

      # Step 4: Build webhook URL for expressions
      base_url = "https://myworkflowapp.com"
      full_url = Webhook.build_webhook_url(base_url, :resume, resume_id)

      assert String.contains?(full_url, resume_id)
      assert String.starts_with?(full_url, base_url)

      # Step 5: Validate state transitions
      assert :ok = Webhook.validate_state_transition(:pending, :active)
      assert :ok = Webhook.validate_state_transition(:active, :consumed)
    end

    test "validates complete webhook lifecycle" do
      states = [:pending, :active, :consumed, :expired]

      # All states should be valid
      Enum.each(states, fn state ->
        assert :ok = Webhook.validate_webhook_state(state)
      end)

      # Test valid transitions
      assert :ok = Webhook.validate_state_transition(:pending, :active)
      assert :ok = Webhook.validate_state_transition(:active, :consumed)
      assert :ok = Webhook.validate_state_transition(:pending, :expired)
      assert :ok = Webhook.validate_state_transition(:active, :expired)

      # Test that final states cannot transition
      final_states = [:consumed, :expired]

      Enum.each(final_states, fn final_state ->
        Enum.each(states -- [final_state], fn other_state ->
          assert {:error, _} = Webhook.validate_state_transition(final_state, other_state)
        end)
      end)
    end
  end
end
