defmodule Prana.Integrations.Wait.WaitActionTest do
  use ExUnit.Case, async: false

  alias Prana.Integrations.Wait.WaitAction

  describe "prepare/1" do
    test "webhook mode generates resume URLs" do
      input_map = %{
        "mode" => "webhook",
        "timeout_hours" => 24,
        "base_url" => "https://myapp.com",
        "$execution" => %{"id" => "exec_123"}
      }

      {:ok, preparation_data} = WaitAction.prepare(input_map)

      assert preparation_data.timeout_hours == 24
      assert String.starts_with?(preparation_data.resume_id, "exec_123_")
      assert String.starts_with?(preparation_data.webhook_url, "https://myapp.com/webhook/workflow/resume/")
      assert preparation_data.execution_id == "exec_123"
      assert %DateTime{} = preparation_data.prepared_at
    end

    test "webhook mode works without base_url" do
      input_map = %{
        "mode" => "webhook",
        "timeout_hours" => 12,
        "$execution" => %{"id" => "exec_456"}
      }

      {:ok, preparation_data} = WaitAction.prepare(input_map)

      assert preparation_data.timeout_hours == 12
      assert String.starts_with?(preparation_data.resume_id, "exec_456_")
      assert preparation_data.webhook_url == nil
      assert preparation_data.execution_id == "exec_456"
    end

    test "webhook mode returns error for invalid timeout_hours" do
      input_map = %{
        "mode" => "webhook",
        "timeout_hours" => -1,
        "$execution" => %{"id" => "exec_123"}
      }

      {:error, reason} = WaitAction.prepare(input_map)
      assert reason =~ "timeout_hours must be a positive number"
    end

    test "interval mode calculates timing correctly" do
      input_map = %{
        "mode" => "interval",
        "duration" => 30,
        "unit" => "seconds"
      }

      {:ok, preparation_data} = WaitAction.prepare(input_map)

      assert preparation_data.mode == "interval"
      assert preparation_data.duration_ms == 30_000
      assert %DateTime{} = preparation_data.resume_at
      assert %DateTime{} = preparation_data.prepared_at
      
      # Resume time should be in the future
      assert DateTime.after?(preparation_data.resume_at, preparation_data.prepared_at)
    end

    test "schedule mode validates and parses datetime" do
      future_time = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601()
      
      input_map = %{
        "mode" => "schedule",
        "schedule_at" => future_time,
        "timezone" => "UTC"
      }

      {:ok, preparation_data} = WaitAction.prepare(input_map)

      assert preparation_data.mode == "schedule"
      assert preparation_data.timezone == "UTC"
      assert %DateTime{} = preparation_data.schedule_at
      assert %DateTime{} = preparation_data.prepared_at
      assert preparation_data.duration_ms > 0
    end

    test "schedule mode returns error for past datetime" do
      past_time = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.to_iso8601()
      
      input_map = %{
        "mode" => "schedule",
        "schedule_at" => past_time
      }

      {:error, reason} = WaitAction.prepare(input_map)
      assert reason =~ "schedule_at must be in the future"
    end

    test "returns error for missing mode" do
      input_map = %{}
      
      {:error, reason} = WaitAction.prepare(input_map)
      assert reason == "mode is required"
    end

    test "returns error for invalid mode" do
      input_map = %{"mode" => "invalid"}
      
      {:error, reason} = WaitAction.prepare(input_map)
      assert reason =~ "mode must be 'interval', 'schedule', or 'webhook'"
    end
  end

  describe "execute/1" do
    test "webhook mode creates suspension with preparation data" do
      input_map = %{
        "mode" => "webhook",
        "timeout_hours" => 24,
        "$preparation" => %{
          "current_node" => %{
            resume_id: "exec_123_AbC123",
            webhook_url: "https://myapp.com/webhook/workflow/resume/exec_123_AbC123"
          }
        }
      }

      {:suspend, :webhook, suspension_data} = WaitAction.execute(input_map)

      assert suspension_data.mode == "webhook"
      assert suspension_data.timeout_hours == 24
      assert suspension_data.resume_id == "exec_123_AbC123"
      assert suspension_data.webhook_url == "https://myapp.com/webhook/workflow/resume/exec_123_AbC123"
      assert %DateTime{} = suspension_data.started_at
      assert %DateTime{} = suspension_data.expires_at
    end

    test "interval mode creates proper suspension" do
      input_map = %{
        "mode" => "interval",
        "duration" => 30,
        "unit" => "seconds"
      }

      {:suspend, :interval, suspension_data} = WaitAction.execute(input_map)

      assert suspension_data.mode == "interval"
      assert suspension_data.duration_ms == 30_000
      assert %DateTime{} = suspension_data.started_at
      assert %DateTime{} = suspension_data.resume_at
    end
  end

  describe "resume/2" do
    test "webhook mode processes resume data correctly" do
      suspend_data = %{
        mode: "webhook",
        pass_through: true,
        input_data: %{"original" => "data"},
        expires_at: DateTime.utc_now() |> DateTime.add(3600, :second)
      }
      
      resume_input = %{"webhook_payload" => "received"}

      {:ok, output_data} = WaitAction.resume(suspend_data, resume_input)

      assert output_data["original"] == "data"
      assert output_data["webhook_payload"] == "received"
    end

    test "webhook mode returns error for expired webhook" do
      suspend_data = %{
        mode: "webhook",
        expires_at: DateTime.utc_now() |> DateTime.add(-3600, :second)
      }
      
      resume_input = %{"webhook_payload" => "received"}

      {:error, error} = WaitAction.resume(suspend_data, resume_input)

      assert error.type == "webhook_timeout"
      assert error.message == "Webhook has expired"
    end

    test "webhook mode without pass_through returns only resume data" do
      suspend_data = %{
        mode: "webhook",
        pass_through: false,
        input_data: %{"original" => "data"},
        expires_at: DateTime.utc_now() |> DateTime.add(3600, :second)
      }
      
      resume_input = %{"webhook_payload" => "received"}

      {:ok, output_data} = WaitAction.resume(suspend_data, resume_input)

      assert output_data == %{"webhook_payload" => "received"}
      refute Map.has_key?(output_data, "original")
    end

    test "interval mode validates timing before resuming" do
      future_resume = DateTime.utc_now() |> DateTime.add(3600, :second)
      
      suspend_data = %{
        mode: "interval",
        pass_through: true,
        input_data: %{"test" => "data"},
        resume_at: future_resume
      }

      {:error, error} = WaitAction.resume(suspend_data, %{})

      assert error.type == "interval_not_ready"
      assert error.message == "Interval duration not yet elapsed"
    end

    test "interval mode resumes successfully when time has passed" do
      past_resume = DateTime.utc_now() |> DateTime.add(-3600, :second)
      
      suspend_data = %{
        mode: "interval",
        pass_through: true,
        input_data: %{"test" => "data"},
        resume_at: past_resume
      }

      {:ok, output_data} = WaitAction.resume(suspend_data, %{})

      assert output_data == %{"test" => "data"}
    end

    test "schedule mode validates timing before resuming" do
      future_schedule = DateTime.utc_now() |> DateTime.add(3600, :second)
      
      suspend_data = %{
        mode: "schedule",
        pass_through: true,
        input_data: %{"test" => "data"},
        schedule_at: future_schedule
      }

      {:error, error} = WaitAction.resume(suspend_data, %{})

      assert error.type == "schedule_not_ready"
      assert error.message == "Scheduled time has not yet arrived"
    end

    test "schedule mode resumes successfully when time has arrived" do
      past_schedule = DateTime.utc_now() |> DateTime.add(-3600, :second)
      
      suspend_data = %{
        mode: "schedule",
        pass_through: true,
        input_data: %{"test" => "data"},
        schedule_at: past_schedule
      }

      {:ok, output_data} = WaitAction.resume(suspend_data, %{})

      assert output_data == %{"test" => "data"}
    end

    test "returns error for unknown suspension mode" do
      suspend_data = %{mode: "unknown"}
      
      {:error, reason} = WaitAction.resume(suspend_data, %{})

      assert reason =~ "Unknown suspension mode"
    end
  end

  describe "end-to-end webhook workflow" do
    test "complete webhook prepare/execute/resume cycle" do
      # 1. Preparation phase
      prepare_input = %{
        "mode" => "webhook",
        "timeout_hours" => 24,
        "base_url" => "https://myapp.com",
        "$execution" => %{"id" => "exec_workflow_123"}
      }

      {:ok, preparation_data} = WaitAction.prepare(prepare_input)
      
      assert String.starts_with?(preparation_data.resume_id, "exec_workflow_123_")
      assert String.contains?(preparation_data.webhook_url, preparation_data.resume_id)

      # 2. Execution phase with preparation data
      execute_input = %{
        "mode" => "webhook",
        "timeout_hours" => 24,
        "base_url" => "https://myapp.com",
        "pass_through" => true,
        "original_data" => "preserved",
        "$preparation" => %{
          "current_node" => preparation_data
        }
      }

      {:suspend, :webhook, suspension_data} = WaitAction.execute(execute_input)
      
      assert suspension_data.resume_id == preparation_data.resume_id
      assert suspension_data.webhook_url == preparation_data.webhook_url
      assert suspension_data.pass_through == true
      assert suspension_data.input_data["original_data"] == "preserved"

      # 3. Resume phase
      webhook_payload = %{
        "user_input" => "approved",
        "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

      {:ok, final_output} = WaitAction.resume(suspension_data, webhook_payload)
      
      # Should merge original data with webhook payload
      assert final_output["original_data"] == "preserved"
      assert final_output["user_input"] == "approved"
      assert final_output["timestamp"] != nil
    end
  end
end