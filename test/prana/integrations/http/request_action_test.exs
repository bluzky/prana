defmodule Prana.Integrations.HTTP.RequestActionTest do
  use ExUnit.Case, async: true

  alias Prana.Core.Error
  alias Prana.Integrations.HTTP.RequestAction

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

      assert {:error, %Error{code: "action_error", message: "URL is required"}, "error"} =
               RequestAction.execute(input_map, %{})
    end

    test "validates HTTP method" do
      input_map = %{"url" => "https://example.com", "method" => "INVALID"}

      assert {:error, %Error{code: "action_error", message: "Unsupported HTTP method: INVALID"}, "error"} =
               RequestAction.execute(input_map, %{})
    end

    test "validates headers parameter" do
      input_map = %{
        "url" => "https://example.com",
        "method" => "GET",
        "headers" => "invalid"
      }

      assert {:error, %Error{code: "action_error", message: "Headers must be a map"}, "error"} =
               RequestAction.execute(input_map, %{})
    end

    test "validates timeout parameter" do
      input_map = %{
        "url" => "https://example.com",
        "method" => "GET",
        "timeout" => "invalid"
      }

      assert {:error, %Error{code: "action_error", message: "Timeout must be an integer (milliseconds)"}, "error"} =
               RequestAction.execute(input_map, %{})
    end

    test "validates params parameter" do
      input_map = %{
        "url" => "https://example.com",
        "method" => "GET",
        "params" => "invalid"
      }

      assert {:error, %Error{code: "action_error", message: "Params must be a map"}, "error"} =
               RequestAction.execute(input_map, %{})
    end

    test "validates authentication configuration" do
      input_map = %{
        "url" => "https://example.com",
        "method" => "GET",
        "auth" => %{"type" => "invalid"}
      }

      assert {:error, %Error{code: "action_error", message: "Invalid authentication configuration"}, "error"} =
               RequestAction.execute(input_map, %{})
    end
  end

  describe "RequestAction resume/3" do
    test "returns error for unsupported resume operation" do
      assert {:error, "HTTP request action does not support resume"} =
               RequestAction.resume(%{}, %{}, %{})
    end
  end

end
