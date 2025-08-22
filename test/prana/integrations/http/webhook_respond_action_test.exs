defmodule Prana.Integrations.HTTP.WebhookRespondActionTest do
  use ExUnit.Case, async: true

  alias Prana.Integrations.HTTP.WebhookRespondAction

  describe "specification/0" do
    test "returns correct action specification" do
      spec = WebhookRespondAction.specification()

      assert spec.name == "http.webhook_respond"
      assert spec.display_name == "Webhook Respond"
      assert spec.type == :action
      assert spec.input_ports == ["main"]
      assert spec.output_ports == ["main", "error"]
      assert spec.module == WebhookRespondAction
    end
  end

  describe "validate_params/1" do
    test "validates text response successfully" do
      params = %{
        "respond_with" => "text",
        "status_code" => 200,
        "headers" => %{"Content-Type" => "text/plain"},
        "text_data" => "Hello World"
      }

      assert {:ok, validated} = WebhookRespondAction.validate_params(params)
      assert validated.respond_with == "text"
      assert validated.status_code == 200
      assert validated.text_data == "Hello World"
    end

    test "validates JSON response successfully" do
      params = %{
        "respond_with" => "json",
        "status_code" => 200,
        "headers" => %{},
        "json_data" => %{"success" => true, "result" => "processed"}
      }

      assert {:ok, validated} = WebhookRespondAction.validate_params(params)
      assert validated.respond_with == "json"
      assert validated.json_data == %{"success" => true, "result" => "processed"}
    end

    test "validates redirect response successfully" do
      params = %{
        "respond_with" => "redirect",
        "status_code" => 302,
        "redirect_url" => "https://example.com/success",
        "redirect_type" => "temporary"
      }

      assert {:ok, validated} = WebhookRespondAction.validate_params(params)
      assert validated.respond_with == "redirect"
      assert validated.redirect_url == "https://example.com/success"
    end

    test "validates no_data response successfully" do
      params = %{
        "respond_with" => "no_data",
        "status_code" => 204
      }

      assert {:ok, validated} = WebhookRespondAction.validate_params(params)
      assert validated.respond_with == "no_data"
      assert validated.status_code == 204
    end

    test "fails validation when text_data is missing for text type" do
      params = %{
        "respond_with" => "text",
        "status_code" => 200
      }

      assert {:error, errors} = WebhookRespondAction.validate_params(params)
      assert "text_data is required when respond_with is 'text'" in errors
    end

    test "fails validation when json_data is missing for json type" do
      params = %{
        "respond_with" => "json",
        "status_code" => 200
      }

      assert {:error, errors} = WebhookRespondAction.validate_params(params)
      assert "json_data is required when respond_with is 'json'" in errors
    end

    test "fails validation when redirect_url is missing for redirect type" do
      params = %{
        "respond_with" => "redirect",
        "status_code" => 302
      }

      assert {:error, errors} = WebhookRespondAction.validate_params(params)
      assert "redirect_url is required when respond_with is 'redirect'" in errors
    end

    test "fails validation for invalid respond_with value" do
      params = %{
        "respond_with" => "invalid_type"
      }

      assert {:error, errors} = WebhookRespondAction.validate_params(params)
      assert length(errors) > 0
    end
  end

  describe "execute/2" do
    test "suspends with webhook response data for text response" do
      params = %{
        "respond_with" => "text",
        "status_code" => 200,
        "headers" => %{"Custom-Header" => "value"},
        "text_data" => "Processing complete"
      }

      context = %{
        execution_id: "exec_123",
        node_id: "respond_node_1"
      }

      assert {:suspend, :webhook_response, suspension_data} =
               WebhookRespondAction.execute(params, context)

      assert suspension_data["type"] == :webhook_response
      assert suspension_data["execution_id"] == "exec_123"
      assert suspension_data["node_id"] == "respond_node_1"
      assert suspension_data["response_config"].respond_with == "text"
      assert suspension_data["response_config"].text == "Processing complete"
      assert suspension_data["response_config"].status_code == 200
      assert suspension_data["response_config"].headers == %{"Custom-Header" => "value"}
      assert %DateTime{} = suspension_data["suspended_at"]
    end

    test "suspends with webhook response data for JSON response" do
      params = %{
        "respond_with" => "json",
        "status_code" => 201,
        "json_data" => %{"id" => 123, "status" => "created"}
      }

      context = %{execution_id: "exec_456", node_id: "respond_node_2"}

      assert {:suspend, :webhook_response, suspension_data} =
               WebhookRespondAction.execute(params, context)

      assert suspension_data["response_config"].respond_with == "json"
      assert suspension_data["response_config"].json_data == %{"id" => 123, "status" => "created"}
      assert suspension_data["response_config"].status_code == 201
    end

    test "suspends with webhook response data for redirect response" do
      params = %{
        "respond_with" => "redirect",
        "status_code" => 302,
        "redirect_url" => "https://app.com/success",
        "redirect_type" => "temporary"
      }

      context = %{execution_id: "exec_789", node_id: "respond_node_3"}

      assert {:suspend, :webhook_response, suspension_data} =
               WebhookRespondAction.execute(params, context)

      assert suspension_data["response_config"].respond_with == "redirect"
      assert suspension_data["response_config"].redirect_url == "https://app.com/success"
      assert suspension_data["response_config"].redirect_type == "temporary"
    end

    test "suspends with webhook response data for no_data response" do
      params = %{
        "respond_with" => "no_data",
        "status_code" => 204
      }

      context = %{execution_id: "exec_000", node_id: "respond_node_4"}

      assert {:suspend, :webhook_response, suspension_data} =
               WebhookRespondAction.execute(params, context)

      assert suspension_data["response_config"].respond_with == "no_data"
      assert suspension_data["response_config"].status_code == 204
    end
  end

  describe "resume/3" do
    test "resumes successfully with nil data" do
      resume_data = %{response_sent_at: ~U[2025-01-23 10:30:00Z]}

      assert {:ok, nil, "main"} =
               WebhookRespondAction.resume(%{}, %{}, resume_data)
    end

    test "resumes successfully with nil data when no resume data provided" do
      resume_data = %{}

      assert {:ok, nil, "main"} =
               WebhookRespondAction.resume(%{}, %{}, resume_data)
    end
  end

  describe "suspendable?/0" do
    test "returns true" do
      assert WebhookRespondAction.suspendable?() == true
    end
  end
end
