defmodule Prana.Integrations.HTTP.WebhookRespondActionTest do
  use ExUnit.Case, async: true

  alias Prana.Integrations.HTTP.WebhookRespondAction

  describe "definition/0" do
    test "returns correct action definition" do
      spec = WebhookRespondAction.definition()

      assert spec.name == "http.webhook_respond"
      assert spec.display_name == "Webhook Respond"
      assert spec.type == :action
      assert spec.input_ports == ["main"]
      assert spec.output_ports == ["main", "error"]
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
