defmodule Prana.NodeSettingsTest do
  use ExUnit.Case, async: true
  alias Prana.NodeSettings

  describe "new/1" do
    test "creates settings with default values" do
      settings = NodeSettings.new(%{})
      
      assert settings.retry_on_failed == false
      assert settings.max_retries == 1
      assert settings.retry_delay_ms == 1000
    end

    test "creates settings with custom values" do
      settings = NodeSettings.new(%{
        retry_on_failed: true,
        max_retries: 3,
        retry_delay_ms: 5000
      })
      
      assert settings.retry_on_failed == true
      assert settings.max_retries == 3
      assert settings.retry_delay_ms == 5000
    end

    test "validates max_retries minimum value through cast_and_validate" do
      assert {:error, %{errors: %{max_retries: _}}} = NodeSettings.cast_and_validate(%{max_retries: 0})
    end

    test "validates max_retries maximum value through cast_and_validate" do
      assert {:error, %{errors: %{max_retries: _}}} = NodeSettings.cast_and_validate(%{max_retries: 11})
    end

    test "validates retry_delay_ms minimum value through cast_and_validate" do
      assert {:error, %{errors: %{retry_delay_ms: _}}} = NodeSettings.cast_and_validate(%{retry_delay_ms: -1})
    end

    test "validates retry_delay_ms maximum value through cast_and_validate" do
      assert {:error, %{errors: %{retry_delay_ms: _}}} = NodeSettings.cast_and_validate(%{retry_delay_ms: 60_001})
    end
  end

  describe "default/0" do
    test "creates default settings" do
      settings = NodeSettings.default()
      
      assert settings.retry_on_failed == false
      assert settings.max_retries == 1
      assert settings.retry_delay_ms == 1000
    end
  end

  describe "from_map/1" do
    test "loads settings from string-keyed map" do
      data = %{
        "retry_on_failed" => true,
        "max_retries" => 5,
        "retry_delay_ms" => 2500
      }
      
      settings = NodeSettings.from_map(data)
      
      assert settings.retry_on_failed == true
      assert settings.max_retries == 5
      assert settings.retry_delay_ms == 2500
    end

    test "loads settings with partial data (uses defaults)" do
      data = %{"retry_on_failed" => true}
      
      settings = NodeSettings.from_map(data)
      
      assert settings.retry_on_failed == true
      assert settings.max_retries == 1
      assert settings.retry_delay_ms == 1000
    end

    test "loads settings from atom-keyed map" do
      data = %{
        retry_on_failed: true,
        max_retries: 3,
        retry_delay_ms: 1500
      }
      
      settings = NodeSettings.from_map(data)
      
      assert settings.retry_on_failed == true
      assert settings.max_retries == 3
      assert settings.retry_delay_ms == 1500
    end

    test "raises on invalid data" do
      assert_raise MatchError, fn ->
        NodeSettings.from_map(%{"max_retries" => "invalid"})
      end
    end
  end

  describe "to_map/1" do
    test "converts settings to map" do
      settings = NodeSettings.new(%{
        retry_on_failed: true,
        max_retries: 3,
        retry_delay_ms: 2000
      })
      
      map = NodeSettings.to_map(settings)
      
      assert map == %{
        retry_on_failed: true,
        max_retries: 3,
        retry_delay_ms: 2000
      }
    end

    test "round-trip serialization works" do
      original_settings = NodeSettings.new(%{
        retry_on_failed: true,
        max_retries: 5,
        retry_delay_ms: 3500
      })
      
      map = NodeSettings.to_map(original_settings)
      restored_settings = NodeSettings.from_map(map)
      
      assert original_settings == restored_settings
    end
  end


  describe "edge cases and validation" do
    test "accepts minimum valid values" do
      settings = NodeSettings.new(%{
        retry_on_failed: false,
        max_retries: 1,
        retry_delay_ms: 0
      })
      
      assert settings.retry_on_failed == false
      assert settings.max_retries == 1
      assert settings.retry_delay_ms == 0
    end

    test "accepts maximum valid values" do
      settings = NodeSettings.new(%{
        retry_on_failed: true,
        max_retries: 10,
        retry_delay_ms: 60_000
      })
      
      assert settings.retry_on_failed == true
      assert settings.max_retries == 10
      assert settings.retry_delay_ms == 60_000
    end

    test "handles boolean conversion from strings" do
      settings = NodeSettings.from_map(%{
        "retry_on_failed" => "true"
      })
      
      assert settings.retry_on_failed == true
    end
  end
end