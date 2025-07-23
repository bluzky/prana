defmodule Prana.Integrations.HTTP.WebhookActionTest do
  use ExUnit.Case, async: true

  alias Prana.Integrations.HTTP.WebhookAction

  describe "WebhookAction execute/2" do
    test "returns request params from context input" do
      context = %{
        "$input" => %{
          "main" => %{
            "method" => "POST",
            "path" => "/webhook",
            "headers" => %{"content-type" => "application/json"},
            "body" => %{"data" => "test"}
          }
        }
      }

      assert {:ok, result, "main"} = WebhookAction.execute(%{}, context)
      assert result == %{
        "method" => "POST",
        "path" => "/webhook",
        "headers" => %{"content-type" => "application/json"},
        "body" => %{"data" => "test"}
      }
    end

    test "returns nil when no input in context" do
      context = %{"$input" => %{}}
      
      assert {:ok, result, "main"} = WebhookAction.execute(%{}, context)
      assert result == nil
    end

    test "returns nil when no context provided" do
      assert {:ok, result, "main"} = WebhookAction.execute(%{}, %{})
      assert result == nil
    end
  end

  describe "WebhookAction resume/3" do
    test "returns error for unsupported resume operation" do
      assert {:error, "Resume not supported"} =
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
