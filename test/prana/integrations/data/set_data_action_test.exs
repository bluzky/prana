defmodule Prana.Integrations.Data.SetDataActionTest do
  use ExUnit.Case, async: true

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

      assert {:error, error} = SetDataAction.execute(params, %{})
      assert error == "Parameter 'mapping_map' must be a map"
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

      assert {:error, error} = SetDataAction.execute(params, %{})
      assert error == "Parameter 'json_template' must be a string"
    end

    test "returns error for invalid JSON" do
      params = %{
        "mode" => "json",
        "json_template" => ~s|{"invalid": json}|
      }

      assert {:error, error} = SetDataAction.execute(params, %{})
      assert String.starts_with?(error, "JSON parsing failed:")
    end

    test "returns error for malformed JSON" do
      params = %{
        "mode" => "json",
        "json_template" => ~s|{"unclosed": "object"|
      }

      assert {:error, error} = SetDataAction.execute(params, %{})
      assert String.starts_with?(error, "JSON parsing failed:")
    end
  end

  describe "execute/2 - error handling" do
    test "returns error for invalid mode" do
      params = %{"mode" => "invalid_mode"}

      assert {:error, error} = SetDataAction.execute(params, %{})
      assert error == "Invalid mode 'invalid_mode'. Supported modes: 'manual', 'json'"
    end

    test "returns error for unknown mode" do
      params = %{"mode" => "xml"}

      assert {:error, error} = SetDataAction.execute(params, %{})
      assert error == "Invalid mode 'xml'. Supported modes: 'manual', 'json'"
    end
  end

  describe "specification/0" do
    test "returns correct action specification" do
      spec = SetDataAction.specification()

      assert spec.name == "data.set_data"
      assert spec.display_name == "Set Data"
      assert spec.description == "Create or transform data using templates in manual or json mode"
      assert spec.type == :action
      assert spec.module == SetDataAction
      assert spec.input_ports == ["main"]
      assert spec.output_ports == ["main", "error"]
    end
  end
end