defmodule Prana.Integrations.Wait.WaitActionTest do
  use ExUnit.Case, async: false

  alias Prana.Integrations.Wait.WaitAction
  alias Prana.Node

  describe "prepare/1" do
    test "webhook mode generates resume URLs" do
      node = %Node{
        key: "test_node",
        name: "Test Wait Node",
        type: "wait.wait",
        params: %{
          "mode" => "webhook",
          "timeout_hours" => 24,
          "base_url" => "https://myapp.com",
          "$execution" => %{"id" => "exec_123"}
        }
      }

      {:ok, preparation_data} = WaitAction.prepare(node)

      assert preparation_data.timeout_hours == 24
      assert String.starts_with?(preparation_data.resume_id, "exec_123_")
      assert String.starts_with?(preparation_data.webhook_url, "https://myapp.com/webhook/workflow/resume/")
      assert preparation_data.execution_id == "exec_123"
      assert %DateTime{} = preparation_data.prepared_at
    end

    test "webhook mode works without base_url" do
      node = %Node{
        key: "test_node",
        name: "Test Wait Node",
        type: "wait.wait",
        params: %{
          "mode" => "webhook",
          "timeout_hours" => 12,
          "$execution" => %{"id" => "exec_456"}
        }
      }

      {:ok, preparation_data} = WaitAction.prepare(node)

      assert preparation_data.timeout_hours == 12
      assert String.starts_with?(preparation_data.resume_id, "exec_456_")
      assert preparation_data.webhook_url == nil
      assert preparation_data.execution_id == "exec_456"
    end

    test "webhook mode returns error for invalid timeout_hours" do
      node = %Node{
        key: "test_node",
        name: "Test Wait Node",
        type: "wait.wait",
        params: %{
          "mode" => "webhook",
          "timeout_hours" => -1,
          "$execution" => %{"id" => "exec_123"}
        }
      }

      {:error, reason} = WaitAction.prepare(node)
      assert reason =~ "timeout_hours must be a positive number"
    end

    test "interval mode calculates timing correctly" do
      node = %Node{
        key: "test_node",
        name: "Test Wait Node",
        type: "wait.wait",
        params: %{
          "mode" => "interval",
          "duration" => 30,
          "unit" => "seconds"
        }
      }

      {:ok, preparation_data} = WaitAction.prepare(node)

      assert preparation_data.mode == "interval"
      assert preparation_data.duration_ms == 30_000
      assert %DateTime{} = preparation_data.resume_at
      assert %DateTime{} = preparation_data.prepared_at

      # Resume time should be in the future
      assert DateTime.after?(preparation_data.resume_at, preparation_data.prepared_at)
    end

    test "schedule mode validates and parses datetime" do
      future_time = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601()

      node = %Node{
        key: "test_node",
        name: "Test Wait Node",
        type: "wait.wait",
        params: %{
          "mode" => "schedule",
          "schedule_at" => future_time,
          "timezone" => "UTC"
        }
      }

      {:ok, preparation_data} = WaitAction.prepare(node)

      assert preparation_data.mode == "schedule"
      assert preparation_data.timezone == "UTC"
      assert %DateTime{} = preparation_data.schedule_at
      assert %DateTime{} = preparation_data.prepared_at
      assert preparation_data.duration_ms > 0
    end

    test "schedule mode returns error for past datetime" do
      past_time = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.to_iso8601()

      node = %Node{
        key: "test_node",
        name: "Test Wait Node",
        type: "wait.wait",
        params: %{
          "mode" => "schedule",
          "schedule_at" => past_time
        }
      }

      {:error, reason} = WaitAction.prepare(node)
      assert reason =~ "schedule_at must be in the future"
    end

    test "returns error for missing mode" do
      node = %Node{
        key: "test_node",
        name: "Test Wait Node",
        type: "wait.wait",
        params: %{}
      }

      {:error, reason} = WaitAction.prepare(node)
      assert reason == "mode is required"
    end

    test "returns error for invalid mode" do
      node = %Node{
        key: "test_node",
        name: "Test Wait Node",
        type: "wait.wait",
        params: %{"mode" => "invalid"}
      }

      {:error, reason} = WaitAction.prepare(node)
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

      {:suspend, :webhook, suspension_data} = WaitAction.execute(input_map, %{})

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
        "duration" => 2,
        "unit" => "minutes"
      }

      {:suspend, :interval, suspension_data} = WaitAction.execute(input_map, %{})

      assert suspension_data.mode == "interval"
      assert suspension_data.duration_ms == 120_000
      assert %DateTime{} = suspension_data.started_at
      assert %DateTime{} = suspension_data.resume_at
    end
  end

  describe "resume/3" do
    test "webhook mode processes resume data correctly" do
      params = %{"mode" => "webhook", "timeout_hours" => 24}
      context = %{}
      resume_data = %{"webhook_payload" => "received"}

      {:ok, output_data} = WaitAction.resume(params, context, resume_data)

      assert output_data["webhook_payload"] == "received"
    end

    test "interval mode resumes successfully" do
      params = %{"mode" => "interval", "duration" => 30, "unit" => "seconds"}
      context = %{}
      resume_data = %{}

      {:ok, output_data} = WaitAction.resume(params, context, resume_data)

      assert output_data == %{}
    end

    test "schedule mode resumes successfully" do
      params = %{"mode" => "schedule", "schedule_at" => DateTime.to_iso8601(DateTime.utc_now())}
      context = %{}
      resume_data = %{}

      {:ok, output_data} = WaitAction.resume(params, context, resume_data)

      assert output_data == %{}
    end

    test "returns error for unknown suspension mode" do
      params = %{"mode" => "unknown"}
      context = %{}
      resume_data = %{}

      {:error, reason} = WaitAction.resume(params, context, resume_data)

      assert reason =~ "Unknown suspension mode"
    end
  end

  describe "end-to-end webhook workflow" do
    test "complete webhook prepare/execute/resume cycle" do
      # 1. Preparation phase
      prepare_node = %Node{
        key: "test_node",
        name: "Test Wait Node",
        type: "wait.wait",
        params: %{
          "mode" => "webhook",
          "timeout_hours" => 24,
          "base_url" => "https://myapp.com",
          "$execution" => %{"id" => "exec_workflow_123"}
        }
      }

      {:ok, preparation_data} = WaitAction.prepare(prepare_node)

      assert String.starts_with?(preparation_data.resume_id, "exec_workflow_123_")
      assert String.contains?(preparation_data.webhook_url, preparation_data.resume_id)

      # 2. Execution phase with preparation data
      execute_input = %{
        "mode" => "webhook",
        "timeout_hours" => 24,
        "base_url" => "https://myapp.com",
        "$preparation" => %{
          "current_node" => preparation_data
        }
      }

      {:suspend, :webhook, suspension_data} = WaitAction.execute(execute_input, %{})

      assert suspension_data.resume_id == preparation_data.resume_id
      assert suspension_data.webhook_url == preparation_data.webhook_url

      # 3. Resume phase
      webhook_payload = %{
        "user_input" => "approved",
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now())
      }

      params = %{"mode" => "webhook", "timeout_hours" => 24}
      context = %{}

      {:ok, final_output} = WaitAction.resume(params, context, webhook_payload)

      # Should return the webhook payload
      assert final_output["user_input"] == "approved"
      assert final_output["timestamp"] != nil
    end
  end
end
