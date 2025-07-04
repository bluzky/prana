defmodule Prana.Integrations.HTTPTest do
  use ExUnit.Case, async: true
  
  alias Prana.Integrations.HTTP
  alias Prana.Integrations.HTTP.RequestAction
  alias Prana.Integrations.HTTP.WebhookAction

  describe "HTTP Integration definition/0" do
    test "returns integration definition with correct structure" do
      definition = HTTP.definition()
      
      assert definition.name == "http"
      assert definition.display_name == "HTTP"
      assert definition.description == "HTTP requests and webhook handling"
      assert definition.version == "1.0.0"
      assert definition.category == "network"
      assert is_map(definition.actions)
      assert Map.has_key?(definition.actions, "request")
      assert Map.has_key?(definition.actions, "webhook")
    end
    
    
    test "request action has correct configuration" do
      definition = HTTP.definition()
      request_action = definition.actions["request"]
      
      assert request_action.name == "request"
      assert request_action.display_name == "HTTP Request"
      assert request_action.module == RequestAction
      assert request_action.input_ports == ["input"]
      assert request_action.output_ports == ["success", "error", "timeout"]
      assert request_action.default_success_port == "success"
      assert request_action.default_error_port == "error"
    end
    
    test "webhook action has correct configuration" do
      definition = HTTP.definition()
      webhook_action = definition.actions["webhook"]
      
      assert webhook_action.name == "webhook"
      assert webhook_action.display_name == "Webhook Trigger"
      assert webhook_action.module == WebhookAction
      assert webhook_action.input_ports == ["input"]
      assert webhook_action.output_ports == ["success", "timeout", "error"]
      assert webhook_action.default_success_port == "success"
      assert webhook_action.default_error_port == "error"
    end
  end

  describe "RequestAction prepare/1" do
    test "returns preparation data" do
      node = %{}
      
      assert {:ok, preparation_data} = RequestAction.prepare(node)
      assert Map.has_key?(preparation_data, :prepared_at)
      assert %DateTime{} = preparation_data.prepared_at
    end
  end
  
  describe "RequestAction execute/1" do
    test "validates required URL parameter" do
      input_map = %{"method" => "GET"}
      
      assert {:error, %{type: "http_error", message: "URL is required"}, "error"} = 
        RequestAction.execute(input_map)
    end
    
    test "validates HTTP method" do
      input_map = %{"url" => "https://example.com", "method" => "INVALID"}
      
      assert {:error, %{type: "http_error", message: "Unsupported HTTP method: INVALID"}, "error"} = 
        RequestAction.execute(input_map)
    end
    
    test "validates headers parameter" do
      input_map = %{
        "url" => "https://example.com",
        "method" => "GET",
        "headers" => "invalid"
      }
      
      assert {:error, %{type: "http_error", message: "Headers must be a map"}, "error"} = 
        RequestAction.execute(input_map)
    end
    
    test "validates timeout parameter" do
      input_map = %{
        "url" => "https://example.com",
        "method" => "GET",
        "timeout" => "invalid"
      }
      
      assert {:error, %{type: "http_error", message: "Timeout must be an integer (milliseconds)"}, "error"} = 
        RequestAction.execute(input_map)
    end
    
    test "validates params parameter" do
      input_map = %{
        "url" => "https://example.com",
        "method" => "GET",
        "params" => "invalid"
      }
      
      assert {:error, %{type: "http_error", message: "Params must be a map"}, "error"} = 
        RequestAction.execute(input_map)
    end
    
    test "validates retry parameter" do
      input_map = %{
        "url" => "https://example.com",
        "method" => "GET",
        "retry" => "invalid"
      }
      
      assert {:error, %{type: "http_error", message: "Retry must be boolean or integer"}, "error"} = 
        RequestAction.execute(input_map)
    end
    
    test "validates authentication configuration" do
      input_map = %{
        "url" => "https://example.com",
        "method" => "GET",
        "auth" => %{"type" => "invalid"}
      }
      
      assert {:error, %{type: "http_error", message: "Invalid authentication configuration"}, "error"} = 
        RequestAction.execute(input_map)
    end
  end
  
  describe "RequestAction resume/2" do
    test "returns error for unsupported resume operation" do
      assert {:error, "HTTP request action does not support resume"} = 
        RequestAction.resume(%{}, %{})
    end
  end

  describe "WebhookAction prepare/1" do
    test "returns default preparation data" do
      node = %{}
      
      assert {:ok, preparation_data} = WebhookAction.prepare(node)
      assert preparation_data.timeout_hours == 24
      assert preparation_data.webhook_path == "/webhook"
      assert %DateTime{} = preparation_data.prepared_at
    end
    
    test "uses node configuration" do
      node = %{
        config: %{
          "timeout_hours" => 12,
          "webhook_path" => "/custom-webhook"
        }
      }
      
      assert {:ok, preparation_data} = WebhookAction.prepare(node)
      assert preparation_data.timeout_hours == 12
      assert preparation_data.webhook_path == "/custom-webhook"
    end
  end
  
  describe "WebhookAction execute/1" do
    test "suspends with webhook configuration" do
      input_map = %{
        "timeout_hours" => 2,
        "webhook_config" => %{"path" => "/test-webhook"}
      }
      
      assert {:suspend, :webhook, suspend_data} = WebhookAction.execute(input_map)
      assert suspend_data.mode == "webhook"
      assert suspend_data.timeout_hours == 2
      assert suspend_data.webhook_config == %{"path" => "/test-webhook"}
      assert %DateTime{} = suspend_data.started_at
      assert %DateTime{} = suspend_data.expires_at
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
    
    test "validates timeout_hours parameter" do
      input_map = %{"timeout_hours" => -1}
      
      assert {:error, %{type: "webhook_config_error", message: message}, "error"} = 
        WebhookAction.execute(input_map)
      assert message =~ "timeout_hours must be a positive number"
    end
    
    test "validates timeout_hours maximum" do
      input_map = %{"timeout_hours" => 10000}
      
      assert {:error, %{type: "webhook_config_error", message: message}, "error"} = 
        WebhookAction.execute(input_map)
      assert message =~ "timeout_hours must be a positive number between 1 and 8760"
    end
  end
  
  describe "WebhookAction resume/2" do
    test "returns webhook payload when not expired" do
      suspend_data = %{
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
        input_data: %{"original" => "data"}
      }
      
      resume_input = %{"webhook" => "payload"}
      
      assert {:ok, result} = WebhookAction.resume(suspend_data, resume_input)
      assert result.webhook_payload == resume_input
      assert result.original_input == %{"original" => "data"}
      assert %DateTime{} = result.received_at
    end
    
    test "returns timeout error when expired" do
      suspend_data = %{
        expires_at: DateTime.add(DateTime.utc_now(), -3600, :second),
        input_data: %{}
      }
      
      resume_input = %{"webhook" => "payload"}
      
      assert {:error, %{type: "webhook_timeout", message: "Webhook has expired"}} = 
        WebhookAction.resume(suspend_data, resume_input)
    end
    
    test "handles missing expires_at" do
      suspend_data = %{input_data: %{}}
      resume_input = %{"webhook" => "payload"}
      
      assert {:ok, result} = WebhookAction.resume(suspend_data, resume_input)
      assert result.webhook_payload == resume_input
    end
  end
  
  describe "WebhookAction suspendable?/0" do
    test "returns true" do
      assert WebhookAction.suspendable?() == true
    end
  end

  describe "RequestAction schema validation" do
    test "validates required URL field" do
      input_map = %{"method" => "GET"}
      
      assert {:error, errors} = RequestAction.validate_input(input_map)
      assert Enum.any?(errors, &String.contains?(&1, "url"))
    end

    test "validates HTTP method inclusion" do
      input_map = %{"url" => "https://example.com", "method" => "INVALID"}
      
      assert {:error, errors} = RequestAction.validate_input(input_map)
      assert Enum.any?(errors, &String.contains?(&1, "method"))
    end

    test "validates timeout range" do
      input_map = %{"url" => "https://example.com", "timeout" => -1}
      
      assert {:error, errors} = RequestAction.validate_input(input_map)
      assert Enum.any?(errors, &String.contains?(&1, "timeout"))
    end

    test "validates URL format" do
      input_map = %{"url" => "invalid-url"}
      
      assert {:error, errors} = RequestAction.validate_input(input_map)
      assert Enum.any?(errors, &String.contains?(&1, "url"))
    end

    test "validates auth configuration" do
      input_map = %{
        "url" => "https://example.com",
        "auth" => %{"type" => "invalid"}
      }
      
      assert {:error, errors} = RequestAction.validate_input(input_map)
      assert Enum.any?(errors, &String.contains?(&1, "auth"))
    end

    test "casts string numbers to integers" do
      input_map = %{
        "url" => "https://example.com",
        "timeout" => "5000",
        "retry" => "3"
      }
      
      assert {:ok, validated} = RequestAction.validate_input(input_map)
      assert validated.timeout == 5000
      assert validated.retry == 3
    end

    test "applies default values" do
      input_map = %{"url" => "https://example.com"}
      
      assert {:ok, validated} = RequestAction.validate_input(input_map)
      assert validated.method == "GET"
      assert validated.timeout == 5000
      assert validated.retry == 0
      assert validated.headers == %{}
      assert validated.params == %{}
    end

    test "validates nested auth schema" do
      input_map = %{
        "url" => "https://example.com",
        "auth" => %{
          "type" => "basic",
          "username" => "user",
          "password" => "pass"
        }
      }
      
      assert {:ok, validated} = RequestAction.validate_input(input_map)
      assert validated.auth.type == "basic"
      assert validated.auth.username == "user"
      assert validated.auth.password == "pass"
    end

    test "returns input_schema" do
      assert RequestAction.input_schema() == Prana.Integrations.HTTP.RequestAction.HTTPRequestSchema
    end
  end

  describe "WebhookAction schema validation" do
    test "validates timeout_hours range" do
      input_map = %{"timeout_hours" => -1}
      
      assert {:error, errors} = WebhookAction.validate_input(input_map)
      assert Enum.any?(errors, &String.contains?(&1, "timeout_hours"))
    end

    test "validates base_url format" do
      input_map = %{"base_url" => "invalid-url"}
      
      assert {:error, errors} = WebhookAction.validate_input(input_map)
      assert Enum.any?(errors, &String.contains?(&1, "base_url"))
    end

    test "applies default webhook config" do
      input_map = %{}
      
      assert {:ok, validated} = WebhookAction.validate_input(input_map)
      assert validated.timeout_hours == 24.0
      assert validated.webhook_config == %{}
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