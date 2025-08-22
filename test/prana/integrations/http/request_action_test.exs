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

  describe "RequestAction schema validation" do
    test "validates required URL field" do
      input_map = %{"method" => "GET"}

      assert {:error, errors} = RequestAction.validate_params(input_map)
      assert Enum.any?(errors, &String.contains?(&1, "url"))
    end

    test "validates HTTP method inclusion" do
      input_map = %{"url" => "https://example.com", "method" => "INVALID"}

      assert {:error, errors} = RequestAction.validate_params(input_map)
      assert Enum.any?(errors, &String.contains?(&1, "method"))
    end

    test "validates timeout range" do
      input_map = %{"url" => "https://example.com", "timeout" => -1}

      assert {:error, errors} = RequestAction.validate_params(input_map)
      assert Enum.any?(errors, &String.contains?(&1, "timeout"))
    end

    test "validates URL format" do
      input_map = %{"url" => "invalid-url"}

      assert {:error, errors} = RequestAction.validate_params(input_map)
      assert Enum.any?(errors, &String.contains?(&1, "url"))
    end

    test "validates auth configuration" do
      input_map = %{
        "url" => "https://example.com",
        "auth" => %{"type" => "invalid"}
      }

      assert {:error, errors} = RequestAction.validate_params(input_map)
      assert Enum.any?(errors, &String.contains?(&1, "auth"))
    end

    test "casts string numbers to integers" do
      input_map = %{
        "url" => "https://example.com",
        "timeout" => "5000"
      }

      assert {:ok, validated} = RequestAction.validate_params(input_map)
      assert validated.timeout == 5000
    end

    test "applies default values" do
      input_map = %{"url" => "https://example.com"}

      assert {:ok, validated} = RequestAction.validate_params(input_map)
      assert validated.method == "GET"
      assert validated.timeout == 5000
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

      assert {:ok, validated} = RequestAction.validate_params(input_map)
      assert validated.auth.type == "basic"
      assert validated.auth.username == "user"
      assert validated.auth.password == "pass"
    end

    test "returns params_schema" do
      assert RequestAction.params_schema() == Prana.Integrations.HTTP.RequestAction.HTTPRequestSchema
    end
  end
end
