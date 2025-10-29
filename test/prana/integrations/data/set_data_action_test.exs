defmodule Prana.Integrations.Data.SetDataActionTest do
  use ExUnit.Case, async: true

  alias Prana.Core.Error
  alias Prana.Integrations.Data.SetDataAction

  describe "execute/2 - manual mode" do
    test "returns mapping_map when provided" do
      params = %{
        "mode" => "manual",
        "mapping_map" => %{
          "user_id" => 123,
          "full_name" => "John Doe",
          "status" => "processed"
        }
      }

      assert {:ok, result} = SetDataAction.execute(params, %{})

      assert result == %{
               "user_id" => 123,
               "full_name" => "John Doe",
               "status" => "processed"
             }
    end

    test "returns nil when mapping_map is missing" do
      params = %{"mode" => "manual"}

      assert {:ok, nil} = SetDataAction.execute(params, %{})
    end

    test "returns error when mapping_map is not a map" do
      params = %{
        "mode" => "manual",
        "mapping_map" => "not_a_map"
      }

      assert {:error, %Error{code: "param_error", message: "Parameter 'mapping_map' must be a map", details: nil}} = SetDataAction.execute(params, %{})
    end

    test "defaults to manual mode when mode not specified" do
      params = %{
        "mapping_map" => %{"key" => "value"}
      }

      assert {:ok, result} = SetDataAction.execute(params, %{})
      assert result == %{"key" => "value"}
    end
  end

  describe "execute/2 - json mode" do
    test "parses valid JSON template" do
      json_string = ~s|{"user":{"id":456,"name":"JANE DOE"},"orders":[{"order_id":"ord_1","amount":99.99}]}|

      params = %{
        "mode" => "json",
        "json_template" => json_string
      }

      assert {:ok, result} = SetDataAction.execute(params, %{})

      assert result == %{
               "user" => %{"id" => 456, "name" => "JANE DOE"},
               "orders" => [%{"order_id" => "ord_1", "amount" => 99.99}]
             }
    end

    test "parses JSON array" do
      json_string = ~s|[{"id":1,"name":"Item 1"},{"id":2,"name":"Item 2"}]|

      params = %{
        "mode" => "json",
        "json_template" => json_string
      }

      assert {:ok, result} = SetDataAction.execute(params, %{})

      assert result == [
               %{"id" => 1, "name" => "Item 1"},
               %{"id" => 2, "name" => "Item 2"}
             ]
    end

    test "returns nil when json_template is missing" do
      params = %{"mode" => "json"}

      assert {:ok, nil} = SetDataAction.execute(params, %{})
    end

    test "returns error when json_template is not a string" do
      params = %{
        "mode" => "json",
        "json_template" => %{"not" => "string"}
      }

      assert {:error, %Error{code: "param_error", message: "Parameter 'json_template' must be a string", details: nil}} = SetDataAction.execute(params, %{})
    end

    test "returns error for invalid JSON" do
      params = %{
        "mode" => "json",
        "json_template" => ~s|{"invalid": json}|
      }

      assert {:error, %Error{code: "json_error", message: message, details: nil}} = SetDataAction.execute(params, %{})
      assert String.starts_with?(message, "JSON parsing failed:")
    end

    test "returns error for malformed JSON" do
      params = %{
        "mode" => "json",
        "json_template" => ~s|{"unclosed": "object"|
      }

      assert {:error, %Error{code: "json_error", message: message, details: nil}} = SetDataAction.execute(params, %{})
      assert String.starts_with?(message, "JSON parsing failed:")
    end
  end

  describe "execute/2 - error handling" do
    test "returns error for invalid mode" do
      params = %{"mode" => "invalid_mode"}

      assert {:error, %Error{code: "mode_error", message: "Invalid mode 'invalid_mode'. Supported modes: 'manual', 'json'", details: nil}} = SetDataAction.execute(params, %{})
    end

    test "returns error for unknown mode" do
      params = %{"mode" => "xml"}

      assert {:error, %Error{code: "mode_error", message: "Invalid mode 'xml'. Supported modes: 'manual', 'json'", details: nil}} = SetDataAction.execute(params, %{})
    end
  end

  describe "definition/0" do
    test "returns correct action definition" do
      spec = SetDataAction.definition()

      assert spec.name == "data.set_data"
      assert spec.display_name == "Set Data"
      assert String.starts_with?(spec.description, "Set Data Action - Creates or transforms data using templates")
      assert spec.type == :action
      assert spec.input_ports == ["main"]
      assert spec.output_ports == ["main"]
    end
  end
end
