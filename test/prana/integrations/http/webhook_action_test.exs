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
    test "returns webhook configuration" do
      input_map = %{
        "path" => "/test-webhook"
      }

      assert {:ok, result, "success"} = WebhookAction.execute(input_map, %{})
      assert result.webhook_path == "/test-webhook"
      assert result.allowed_methods == ["POST"]
      assert result.auth_config == %{"type" => "none"}
      assert result.response_type == "immediately"
      assert %DateTime{} = result.configured_at
    end

    test "builds webhook URL from environment variable" do
      # Set environment variable for this test
      original_base_url = System.get_env("PRANA_BASE_URL")
      System.put_env("PRANA_BASE_URL", "https://example.com")

      input_map = %{
        "path" => "/my-webhook"
      }

      assert {:ok, result, "success"} = WebhookAction.execute(input_map, %{})
      assert result.webhook_url == "https://example.com/my-webhook"

      # Restore original environment
      if original_base_url do
        System.put_env("PRANA_BASE_URL", original_base_url)
      else
        System.delete_env("PRANA_BASE_URL")
      end
    end

    test "uses default webhook path" do
      # Set environment variable for this test
      original_base_url = System.get_env("PRANA_BASE_URL")
      System.put_env("PRANA_BASE_URL", "https://example.com")

      input_map = %{}

      assert {:ok, result, "success"} = WebhookAction.execute(input_map, %{})
      assert result.webhook_path == "/webhook"
      assert result.webhook_url == "https://example.com/webhook"

      # Restore original environment
      if original_base_url do
        System.put_env("PRANA_BASE_URL", original_base_url)
      else
        System.delete_env("PRANA_BASE_URL")
      end
    end
  end

  describe "WebhookAction resume/3" do
    test "returns error for unsupported resume operation" do
      assert {:error, "Webhook action does not support resume"} =
               WebhookAction.resume(%{}, %{}, %{})
    end
  end

  describe "WebhookAction suspendable?/0" do
    test "returns false" do
      assert WebhookAction.suspendable?() == false
    end
  end

  describe "WebhookAction schema validation" do
    test "validates invalid HTTP methods" do
      input_map = %{
        "methods" => ["INVALID", "POST"]
      }

      assert {:error, errors} = WebhookAction.validate_params(input_map)
      assert Enum.any?(errors, &String.contains?(&1, "Invalid HTTP methods: INVALID"))
    end

    test "applies default webhook config" do
      input_map = %{}

      assert {:ok, validated} = WebhookAction.validate_params(input_map)
      assert validated.path == "/webhook"
      assert validated.secret == nil
      assert validated.headers == %{}
    end

    test "validates webhook config schema" do
      input_map = %{
        "path" => "/custom-webhook",
        "secret" => "mysecret",
        "headers" => %{"X-Custom" => "value"}
      }

      assert {:ok, validated} = WebhookAction.validate_params(input_map)
      assert validated.path == "/custom-webhook"
      assert validated.secret == "mysecret"
      assert validated.headers == %{"X-Custom" => "value"}
    end

    test "returns params_schema" do
      assert WebhookAction.params_schema() == Prana.Integrations.HTTP.WebhookAction.WebhookConfigSchema
    end
  end

end
