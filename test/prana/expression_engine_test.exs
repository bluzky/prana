defmodule Prana.ExpressionEngineTest do
  use ExUnit.Case, async: true

  alias Prana.ExpressionEngine

  describe "simple field access" do
    setup do
      context = %{
        "input" => %{
          "email" => "john@test.com",
          "age" => 25,
          "is_active" => true,
          "profile" => %{
            "name" => "John Doe",
            "settings" => %{"theme" => "dark"}
          }
        },
        "nodes" => %{
          "api_call" => %{
            "response" => %{"user_id" => 123, "status" => "success"},
            "status_code" => 200
          }
        },
        "variables" => %{
          "api_url" => "https://api.example.com",
          "retry_count" => 3
        }
      }

      {:ok, context: context}
    end

    test "distinguishes between missing paths (nil) and syntax errors (error)" do
      context = %{
        "input" => %{"valid_field" => "value"}
      }

      # Missing paths should return nil
      {:ok, result} = ExpressionEngine.extract("$input.missing_field", context)
      assert result == nil
      
      {:ok, result} = ExpressionEngine.extract("$missing_root.field", context)
      assert result == nil
      
      # Non-expressions should return as-is
      {:ok, result} = ExpressionEngine.extract("not_an_expression", context)
      assert result == "not_an_expression"
      
      # Empty $ should return as-is (not a valid expression)
      {:ok, result} = ExpressionEngine.extract("$", context)
      assert result == "$"
      
      # Valid expressions should work
      {:ok, result} = ExpressionEngine.extract("$input.valid_field", context)
      assert result == "value"
    end

    test "map processing with mixed missing and valid paths" do
      context = %{
        "input" => %{"existing" => "value"},
        "nodes" => %{"step1" => %{"result" => "success"}}
      }
      
      input_map = %{
        "valid1" => "$input.existing",
        "valid2" => "$nodes.step1.result", 
        "missing1" => "$input.nonexistent",
        "missing2" => "$nodes.missing_step.result",
        "missing3" => "$variables.missing_var",
        "static" => "hello"
      }
      
      {:ok, processed} = ExpressionEngine.process_map(input_map, context)
      
      assert processed == %{
        "valid1" => "value",
        "valid2" => "success",
        "missing1" => nil,
        "missing2" => nil, 
        "missing3" => nil,
        "static" => "hello"
      }
    end

    test "extracts simple fields", %{context: context} do
      {:ok, email} = ExpressionEngine.extract("$input.email", context)
      assert email == "john@test.com"

      {:ok, age} = ExpressionEngine.extract("$input.age", context)
      assert age == 25

      {:ok, active} = ExpressionEngine.extract("$input.is_active", context)
      assert active == true
    end

    test "extracts nested fields", %{context: context} do
      {:ok, name} = ExpressionEngine.extract("$input.profile.name", context)
      assert name == "John Doe"

      {:ok, theme} = ExpressionEngine.extract("$input.profile.settings.theme", context)
      assert theme == "dark"

      {:ok, user_id} = ExpressionEngine.extract("$nodes.api_call.response.user_id", context)
      assert user_id == 123
    end

    test "extracts from different context roots", %{context: context} do
      {:ok, api_url} = ExpressionEngine.extract("$variables.api_url", context)
      assert api_url == "https://api.example.com"

      {:ok, status_code} = ExpressionEngine.extract("$nodes.api_call.status_code", context)
      assert status_code == 200
    end

    test "returns non-expressions as-is", %{context: context} do
      {:ok, value} = ExpressionEngine.extract("hello", context)
      assert value == "hello"

      {:ok, value} = ExpressionEngine.extract(123, context)
      assert value == 123

      {:ok, value} = ExpressionEngine.extract(true, context)
      assert value == true

      {:ok, value} = ExpressionEngine.extract(%{"key" => "value"}, context)
      assert value == %{"key" => "value"}
    end

    test "handles missing paths - returns nil", %{context: context} do
      {:ok, result} = ExpressionEngine.extract("$input.nonexistent", context)
      assert result == nil

      {:ok, result} = ExpressionEngine.extract("$nodes.missing.field", context)
      assert result == nil

      {:ok, result} = ExpressionEngine.extract("$variables.nonexistent.deep.path", context)
      assert result == nil
    end
  end

  describe "array access" do
    setup do
      context = %{
        "input" => %{
          "users" => [
            %{"name" => "John", "email" => "john@test.com", "is_active" => true, "role" => "admin"},
            %{"name" => "Jane", "email" => "jane@test.com", "is_active" => true, "role" => "user"},
            %{"name" => "Bob", "email" => "bob@test.com", "is_active" => false, "role" => "user"}
          ],
          "tags" => ["urgent", "customer", "support"]
        },
        "nodes" => %{
          "search_results" => %{
            "items" => [
              %{"title" => "First Result", "score" => 0.95},
              %{"title" => "Second Result", "score" => 0.87}
            ]
          }
        }
      }

      {:ok, context: context}
    end

    test "extracts array elements by index", %{context: context} do
      {:ok, user} = ExpressionEngine.extract("$input.users[0]", context)
      assert user["name"] == "John"

      {:ok, name} = ExpressionEngine.extract("$input.users[1].name", context)
      assert name == "Jane"

      {:ok, tag} = ExpressionEngine.extract("$input.tags[0]", context)
      assert tag == "urgent"
    end

    test "extracts from nested arrays", %{context: context} do
      {:ok, title} = ExpressionEngine.extract("$nodes.search_results.items[0].title", context)
      assert title == "First Result"

      {:ok, score} = ExpressionEngine.extract("$nodes.search_results.items[1].score", context)
      assert score == 0.87
    end

    test "handles array bounds - returns nil", %{context: context} do
      {:ok, result} = ExpressionEngine.extract("$input.users[10]", context)
      assert result == nil
      
      {:ok, result} = ExpressionEngine.extract("$input.tags[5]", context)
      assert result == nil
    end
  end

  describe "filtering with corrected syntax" do
    setup do
      context = %{
        "input" => %{
          "users" => [
            %{"id" => 1, "name" => "John", "email" => "john@test.com", "is_active" => true, "role" => "admin"},
            %{"id" => 2, "name" => "Jane", "email" => "jane@test.com", "is_active" => true, "role" => "user"},
            %{"id" => 3, "name" => "Bob", "email" => "bob@test.com", "is_active" => false, "role" => "user"},
            %{"id" => 4, "name" => "Alice", "email" => "alice@test.com", "is_active" => true, "role" => "admin"}
          ],
          "orders" => [
            %{"id" => 101, "status" => "completed", "amount" => 100, "user_id" => 1},
            %{"id" => 102, "status" => "pending", "amount" => 200, "user_id" => 2},
            %{"id" => 103, "status" => "completed", "amount" => 150, "user_id" => 1},
            %{"id" => 104, "status" => "completed", "amount" => 75, "user_id" => 4}
          ]
        }
      }

      {:ok, context: context}
    end

    test "filters with single condition - returns arrays", %{context: context} do
      {:ok, admin_emails} = ExpressionEngine.extract("$input.users.{role: \"admin\"}.email", context)
      assert admin_emails == ["john@test.com", "alice@test.com"]

      {:ok, active_names} = ExpressionEngine.extract("$input.users.{is_active: true}.name", context)
      assert active_names == ["John", "Jane", "Alice"]

      {:ok, completed_amounts} = ExpressionEngine.extract("$input.orders.{status: \"completed\"}.amount", context)
      assert completed_amounts == [100, 150, 75]
    end

    test "filters with multiple conditions", %{context: context} do
      {:ok, active_admins} = ExpressionEngine.extract("$input.users.{is_active: true, role: \"admin\"}", context)
      assert length(active_admins) == 2
      assert Enum.all?(active_admins, &(&1["is_active"] == true and &1["role"] == "admin"))

      {:ok, user1_completed_orders} =
        ExpressionEngine.extract("$input.orders.{status: \"completed\", user_id: 1}", context)

      assert length(user1_completed_orders) == 2
      assert Enum.all?(user1_completed_orders, &(&1["user_id"] == 1 and &1["status"] == "completed"))
    end

    test "handles no matches - returns empty arrays", %{context: context} do
      {:ok, no_matches} = ExpressionEngine.extract("$input.users.{role: \"nonexistent\"}.name", context)
      assert no_matches == []

      {:ok, no_orders} = ExpressionEngine.extract("$input.orders.{status: \"cancelled\"}.id", context)
      assert no_orders == []
    end

    test "single match still returns array", %{context: context} do
      {:ok, inactive_users} = ExpressionEngine.extract("$input.users.{is_active: false}.name", context)
      # Array with one item
      assert inactive_users == ["Bob"]
    end

    test "filters with different value types", %{context: context} do
      # Boolean filter
      {:ok, active_users} = ExpressionEngine.extract("$input.users.{is_active: true}", context)
      assert length(active_users) == 3

      # Number filter
      {:ok, user_1_orders} = ExpressionEngine.extract("$input.orders.{user_id: 1}", context)
      assert length(user_1_orders) == 2

      # String filter with single quotes
      {:ok, admin_users} = ExpressionEngine.extract("$input.users.{role: 'admin'}", context)
      assert length(admin_users) == 2
    end
  end

  describe "wildcard extraction - always returns arrays" do
    setup do
      context = %{
        "input" => %{
          "users" => [
            %{"name" => "John", "email" => "john@test.com", "skills" => ["elixir", "javascript"]},
            %{"name" => "Jane", "email" => "jane@test.com", "skills" => ["python", "sql"]},
            %{"name" => "Bob", "email" => "bob@test.com", "skills" => ["java", "spring"]}
          ]
        }
      }

      {:ok, context: context}
    end

    test "extracts all values with wildcard", %{context: context} do
      {:ok, names} = ExpressionEngine.extract("$input.users.*.name", context)
      assert names == ["John", "Jane", "Bob"]

      {:ok, emails} = ExpressionEngine.extract("$input.users.*.email", context)
      assert emails == ["john@test.com", "jane@test.com", "bob@test.com"]
    end

    test "extracts all objects with wildcard", %{context: context} do
      {:ok, users} = ExpressionEngine.extract("$input.users.*", context)
      assert length(users) == 3
      assert Enum.all?(users, &is_map/1)
    end

    test "extracts nested arrays with wildcard", %{context: context} do
      {:ok, all_skills} = ExpressionEngine.extract("$input.users.*.skills.*", context)
      assert all_skills == ["elixir", "javascript", "python", "sql", "java", "spring"]
    end

    test "wildcard with empty arrays", %{context: _context} do
      empty_context = %{"input" => %{"users" => []}}
      {:ok, names} = ExpressionEngine.extract("$input.users.*.name", empty_context)
      assert names == []
    end
  end

  describe "map processing" do
    setup do
      context = %{
        "input" => %{
          "user_id" => 123,
          "email" => "john@test.com",
          "users" => [
            %{"name" => "John", "role" => "admin"},
            %{"name" => "Jane", "role" => "user"}
          ]
        },
        "variables" => %{
          "api_url" => "https://api.example.com"
        },
        "nodes" => %{
          "get_user" => %{
            "profile" => %{"avatar_url" => "https://example.com/avatar.jpg"}
          }
        }
      }

      {:ok, context: context}
    end

    test "processes map with expressions", %{context: context} do
      input_map = %{
        "user_id" => "$input.user_id",
        "email" => "$input.email",
        "api_url" => "$variables.api_url",
        "avatar" => "$nodes.get_user.profile.avatar_url",
        # Array result
        "all_names" => "$input.users.*.name",
        # Array result
        "admin_names" => "$input.users.{role: \"admin\"}.name",
        "static_value" => "hello",
        "number_value" => 42
      }

      {:ok, processed} = ExpressionEngine.process_map(input_map, context)

      assert processed == %{
               "user_id" => 123,
               "email" => "john@test.com",
               "api_url" => "https://api.example.com",
               "avatar" => "https://example.com/avatar.jpg",
               "all_names" => ["John", "Jane"],
               "admin_names" => ["John"],
               "static_value" => "hello",
               "number_value" => 42
             }
    end

    test "processes nested maps", %{context: context} do
      input_map = %{
        "user_data" => %{
          "id" => "$input.user_id",
          "contact" => %{
            "email" => "$input.email"
          }
        },
        "config" => %{
          "api_url" => "$variables.api_url",
          # Array in nested structure
          "user_names" => "$input.users.*.name"
        }
      }

      {:ok, processed} = ExpressionEngine.process_map(input_map, context)

      assert processed == %{
               "user_data" => %{
                 "id" => 123,
                 "contact" => %{
                   "email" => "john@test.com"
                 }
               },
               "config" => %{
                 "api_url" => "https://api.example.com",
                 "user_names" => ["John", "Jane"]
               }
             }
    end

    test "handles non-map input", %{context: context} do
      {:ok, result} = ExpressionEngine.process_map("not a map", context)
      assert result == "not a map"

      {:ok, result} = ExpressionEngine.process_map(123, context)
      assert result == 123
    end

    test "handles missing paths in map processing - returns nil", %{context: context} do
      input_map = %{
        "valid" => "$input.email",
        "missing" => "$input.nonexistent.field"
      }

      {:ok, processed} = ExpressionEngine.process_map(input_map, context)
      
      assert processed == %{
        "valid" => "john@test.com",
        "missing" => nil
      }
    end
  end

  describe "complex scenarios" do
    test "workflow node input preparation" do
      context = %{
        "input" => %{
          "operation" => "send_notifications",
          "tenant_id" => "tenant_123"
        },
        "nodes" => %{
          "get_users" => %{
            "response" => %{
              "users" => [
                %{"id" => 1, "email" => "john@test.com", "role" => "admin", "is_active" => true},
                %{"id" => 2, "email" => "jane@test.com", "role" => "user", "is_active" => true},
                %{"id" => 3, "email" => "bob@test.com", "role" => "admin", "is_active" => false}
              ]
            },
            "status_code" => 200
          }
        },
        "variables" => %{
          "api_base_url" => "https://api.example.com",
          "notification_template" => "Welcome {{name}}!"
        }
      }

      # Prepare input for notification node
      notification_input = %{
        "base_url" => "$variables.api_base_url",
        "tenant_id" => "$input.tenant_id",
        "template" => "$variables.notification_template",
        "all_emails" => "$nodes.get_users.response.users.*.email",
        "admin_emails" => "$nodes.get_users.response.users.{role: \"admin\"}.email",
        "active_admin_ids" => "$nodes.get_users.response.users.{role: \"admin\", is_active: true}.id"
      }

      {:ok, prepared} = ExpressionEngine.process_map(notification_input, context)

      assert prepared == %{
               "base_url" => "https://api.example.com",
               "tenant_id" => "tenant_123",
               "template" => "Welcome {{name}}!",
               "all_emails" => ["john@test.com", "jane@test.com", "bob@test.com"],
               "admin_emails" => ["john@test.com", "bob@test.com"],
               # Only John is active admin
               "active_admin_ids" => [1]
             }
    end

    test "expression edge cases" do
      context = %{
        "input" => %{
          "empty_list" => [],
          "null_value" => nil,
          "nested" => %{"deep" => %{"value" => "found"}}
        }
      }

      # Empty expressions should return as-is
      {:ok, "$"} = ExpressionEngine.extract("$", context)

      # Deep nesting should work
      {:ok, value} = ExpressionEngine.extract("$input.nested.deep.value", context)
      assert value == "found"

      # Wildcards on empty arrays should return empty arrays
      {:ok, empty} = ExpressionEngine.extract("$input.empty_list.*", context)
      assert empty == []

      # Accessing nil should return nil (graceful handling)
      {:ok, result} = ExpressionEngine.extract("$input.null_value.field", context)
      assert result == nil
      
      # Accessing missing root should return nil
      {:ok, result} = ExpressionEngine.extract("$nonexistent.field", context)
      assert result == nil
    end
  end
end
