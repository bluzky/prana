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

end
