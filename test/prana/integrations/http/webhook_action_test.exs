defmodule Prana.Integrations.HTTP.WebhookActionTest do
  use ExUnit.Case, async: true
  
  alias Prana.Integrations.HTTP.WebhookAction

  describe "WebhookAction prepare/1" do
    test "returns default preparation data" do
      node = %{}
      
      assert {:ok, preparation_data} = WebhookAction.prepare(node)
      assert preparation_data.webhook_path == "/webhook"
      assert %DateTime{} = preparation_data.prepared_at
    end
    
    test "uses node configuration" do
      node = %{
        config: %{
          "webhook_path" => "/custom-webhook"
        }
      }
      
      assert {:ok, preparation_data} = WebhookAction.prepare(node)
      assert preparation_data.webhook_path == "/custom-webhook"
    end
  end
  
  describe "WebhookAction execute/1" do
    test "suspends with webhook configuration" do
      input_map = %{
        "webhook_config" => %{"path" => "/test-webhook"}
      }
      
      assert {:suspend, :webhook, suspend_data} = WebhookAction.execute(input_map)
      assert suspend_data.mode == "webhook"
      assert suspend_data.webhook_config == %{"path" => "/test-webhook"}
      assert %DateTime{} = suspend_data.started_at
      assert suspend_data.input_data == input_map
    end
    
    test "builds webhook URL when base_url provided" do
      input_map = %{
        "base_url" => "https://example.com",
        "webhook_config" => %{"path" => "/my-webhook"}
      }
      
      assert {:suspend, :webhook, suspend_data} = WebhookAction.execute(input_map)
      assert suspend_data.webhook_url == "https://example.com/my-webhook"
    end
    
    test "uses default webhook path" do
      input_map = %{
        "base_url" => "https://example.com"
      }
      
      assert {:suspend, :webhook, suspend_data} = WebhookAction.execute(input_map)
      assert suspend_data.webhook_url == "https://example.com/webhook"
    end
  end
  
  describe "WebhookAction resume/2" do
    test "returns webhook payload" do
      suspend_data = %{
        input_data: %{"original" => "data"}
      }
      
      resume_input = %{"webhook" => "payload"}
      
      assert {:ok, result} = WebhookAction.resume(suspend_data, resume_input)
      assert result.webhook_payload == resume_input
      assert result.original_input == %{"original" => "data"}
      assert %DateTime{} = result.received_at
    end
  end
  
  describe "WebhookAction suspendable?/0" do
    test "returns true" do
      assert WebhookAction.suspendable?() == true
    end
  end

  describe "WebhookAction schema validation" do
    test "validates base_url format" do
      input_map = %{"base_url" => "invalid-url"}
      
      assert {:error, errors} = WebhookAction.validate_input(input_map)
      assert Enum.any?(errors, &String.contains?(&1, "base_url"))
    end

    test "applies default webhook config" do
      input_map = %{}
      
      assert {:ok, validated} = WebhookAction.validate_input(input_map)
      assert validated.webhook_config.path == "/webhook"
      assert validated.webhook_config.secret == nil
      assert validated.webhook_config.headers == %{}
    end

    test "validates nested webhook config schema" do
      input_map = %{
        "webhook_config" => %{
          "path" => "/custom-webhook",
          "secret" => "mysecret",
          "headers" => %{"X-Custom" => "value"}
        }
      }
      
      assert {:ok, validated} = WebhookAction.validate_input(input_map)
      assert validated.webhook_config.path == "/custom-webhook"
      assert validated.webhook_config.secret == "mysecret"
      assert validated.webhook_config.headers == %{"X-Custom" => "value"}
    end

    test "returns input_schema" do
      assert WebhookAction.input_schema() == Prana.Integrations.HTTP.WebhookAction.WebhookSchema
    end
  end
end