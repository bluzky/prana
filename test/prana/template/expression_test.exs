defmodule Prana.Template.ExpressionTest do
  use ExUnit.Case, async: false

  alias Prana.Template.Expression

  describe "simple field access" do
    setup do
      context = %{
        "$input" => %{
          "email" => "john@test.com",
          "age" => 25,
          "is_active" => true,
          "profile" => %{
            "name" => "John Doe",
            "settings" => %{"theme" => "dark"}
          }
        },
        "$nodes" => %{
          "api_call" => %{
            "response" => %{"user_id" => 123, "status" => "success"},
            "status_code" => 200
          }
        },
        "$variables" => %{
          "api_url" => "https://api.example.com",
          "retry_count" => 3
        }
      }

      {:ok, context: context}
    end

    test "distinguishes between missing paths (nil) and syntax errors (error)" do
      context = %{
        "$input" => %{"valid_field" => "value"}
      }

      # Missing paths should return nil
      {:ok, result} = Expression.extract("$input.missing_field", context)
      assert result == nil

      {:ok, result} = Expression.extract("$missing_root.field", context)
      assert result == nil

      # Non-expressions should return as-is
      {:ok, result} = Expression.extract("not_an_expression", context)
      assert result == "not_an_expression"

      # Empty $ should return as-is (not a valid expression)
      {:ok, result} = Expression.extract("$", context)
      assert result == "$"

      # Valid expressions should work
      {:ok, result} = Expression.extract("$input.valid_field", context)
      assert result == "value"
    end

    test "map processing with mixed missing and valid paths" do
      context = %{
        "$input" => %{"existing" => "value"},
        "$nodes" => %{"step1" => %{"result" => "success"}}
      }

      input_map = %{
        "valid1" => "$input.existing",
        "valid2" => "$nodes.step1.result",
        "missing1" => "$input.nonexistent",
        "missing2" => "$nodes.missing_step.result",
        "missing3" => "$variables.missing_var",
        "static" => "hello"
      }

      {:ok, processed} = Expression.process_map(input_map, context)

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
      {:ok, email} = Expression.extract("$input.email", context)
      assert email == "john@test.com"

      {:ok, age} = Expression.extract("$input.age", context)
      assert age == 25

      {:ok, active} = Expression.extract("$input.is_active", context)
      assert active == true
    end

    test "extracts nested fields", %{context: context} do
      {:ok, name} = Expression.extract("$input.profile.name", context)
      assert name == "John Doe"

      {:ok, theme} = Expression.extract("$input.profile.settings.theme", context)
      assert theme == "dark"

      {:ok, user_id} = Expression.extract("$nodes.api_call.response.user_id", context)
      assert user_id == 123
    end

    test "extracts from different context roots", %{context: context} do
      {:ok, api_url} = Expression.extract("$variables.api_url", context)
      assert api_url == "https://api.example.com"

      {:ok, status_code} = Expression.extract("$nodes.api_call.status_code", context)
      assert status_code == 200
    end

    test "returns non-expressions as-is", %{context: context} do
      {:ok, value} = Expression.extract("hello", context)
      assert value == "hello"

      {:ok, value} = Expression.extract(123, context)
      assert value == 123

      {:ok, value} = Expression.extract(true, context)
      assert value == true

      {:ok, value} = Expression.extract(%{"key" => "value"}, context)
      assert value == %{"key" => "value"}
    end

    test "handles missing paths - returns nil", %{context: context} do
      {:ok, result} = Expression.extract("$input.nonexistent", context)
      assert result == nil

      {:ok, result} = Expression.extract("$nodes.missing.field", context)
      assert result == nil

      {:ok, result} = Expression.extract("$variables.nonexistent.deep.path", context)
      assert result == nil
    end
  end

  describe "array access" do
    setup do
      context = %{
        "$input" => %{
          "users" => [
            %{"name" => "John", "email" => "john@test.com", "is_active" => true, "role" => "admin"},
            %{"name" => "Jane", "email" => "jane@test.com", "is_active" => true, "role" => "user"},
            %{"name" => "Bob", "email" => "bob@test.com", "is_active" => false, "role" => "user"}
          ],
          "tags" => ["urgent", "customer", "support"]
        },
        "$nodes" => %{
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
      {:ok, user} = Expression.extract("$input.users[0]", context)
      assert user["name"] == "John"

      {:ok, name} = Expression.extract("$input.users[1].name", context)
      assert name == "Jane"

      {:ok, tag} = Expression.extract("$input.tags[0]", context)
      assert tag == "urgent"
    end

    test "extracts from nested arrays", %{context: context} do
      {:ok, title} = Expression.extract("$nodes.search_results.items[0].title", context)
      assert title == "First Result"

      {:ok, score} = Expression.extract("$nodes.search_results.items[1].score", context)
      assert score == 0.87
    end

    test "handles array bounds - returns nil", %{context: context} do
      {:ok, result} = Expression.extract("$input.users[10]", context)
      assert result == nil

      {:ok, result} = Expression.extract("$input.tags[5]", context)
      assert result == nil
    end
  end



  describe "map processing" do
    setup do
      context = %{
        "$input" => %{
          "user_id" => 123,
          "email" => "john@test.com",
          "users" => [
            %{"name" => "John", "role" => "admin"},
            %{"name" => "Jane", "role" => "user"}
          ]
        },
        "$variables" => %{
          "api_url" => "https://api.example.com"
        },
        "$nodes" => %{
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
        # Single result from first user
        "first_name" => "$input.users[0].name",
        # Single result from second user
        "second_name" => "$input.users[1].name",
        "static_value" => "hello",
        "number_value" => 42
      }

      {:ok, processed} = Expression.process_map(input_map, context)

      assert processed == %{
               "user_id" => 123,
               "email" => "john@test.com",
               "api_url" => "https://api.example.com",
               "avatar" => "https://example.com/avatar.jpg",
               "first_name" => "John",
               "second_name" => "Jane",
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
          "first_user_name" => "$input.users[0].name"
        }
      }

      {:ok, processed} = Expression.process_map(input_map, context)

      assert processed == %{
               "user_data" => %{
                 "id" => 123,
                 "contact" => %{
                   "email" => "john@test.com"
                 }
               },
               "config" => %{
                 "api_url" => "https://api.example.com",
                 "first_user_name" => "John"
               }
             }
    end

    test "handles non-map input", %{context: context} do
      {:ok, result} = Expression.process_map("not a map", context)
      assert result == "not a map"

      {:ok, result} = Expression.process_map(123, context)
      assert result == 123
    end

    test "handles missing paths in map processing - returns nil", %{context: context} do
      input_map = %{
        "valid" => "$input.email",
        "missing" => "$input.nonexistent.field"
      }

      {:ok, processed} = Expression.process_map(input_map, context)

      assert processed == %{
               "valid" => "john@test.com",
               "missing" => nil
             }
    end
  end

  describe "extended bracket syntax" do
    setup do
      context = %{
        "$input" => %{
          "email" => "test@example.com",
          :atom_email => "atom@example.com",
          "user" => %{
            "0" => "string_zero_value",
            0 => "integer_zero_value"
          },
          "object" => %{
            0 => "integer_key_value",
            "1" => "string_key_value"
          },
          "mixed_keys" => %{
            :name => "John",
            "age" => 25,
            "role" => "admin"
          }
        }
      }

      {:ok, context: context}
    end

    test "string key access with double quotes", %{context: context} do
      {:ok, result} = Expression.extract("$input[\"email\"]", context)
      assert result == "test@example.com"
    end

    test "string key access with single quotes", %{context: context} do
      {:ok, result} = Expression.extract("$input['email']", context)
      assert result == "test@example.com"
    end

    test "atom key access", %{context: context} do
      {:ok, result} = Expression.extract("$input[:atom_email]", context)
      assert result == "atom@example.com"
    end

    test "string number key vs integer key distinction", %{context: context} do
      # String "0" key
      {:ok, result1} = Expression.extract("$input.user[\"0\"]", context)
      assert result1 == "string_zero_value"

      # Integer 0 key  
      {:ok, result2} = Expression.extract("$input.user[0]", context)
      assert result2 == "integer_zero_value"
    end

    test "integer key access in object", %{context: context} do
      {:ok, result} = Expression.extract("$input.object[0]", context) 
      assert result == "integer_key_value"
    end

    test "mixed key types in same object", %{context: context} do
      {:ok, atom_result} = Expression.extract("$input.mixed_keys[:name]", context)
      assert atom_result == "John"

      {:ok, string_result} = Expression.extract("$input.mixed_keys[\"age\"]", context)
      assert string_result == 25

      {:ok, dot_result} = Expression.extract("$input.mixed_keys.role", context)
      assert dot_result == "admin"
    end

    test "simple atom key access works", %{context: _context} do
      simple_context = %{
        "$input" => %{
          :atom_key => "atom_value"
        }
      }

      {:ok, result} = Expression.extract("$input[:atom_key]", simple_context)
      assert result == "atom_value"
    end

    test "nested bracket access with debug", %{context: _context} do
      # Let's test step by step to understand what's happening
      {:ok, result1} = Expression.extract("$input.mixed_keys[:name]", %{
        "$input" => %{
          "mixed_keys" => %{
            :name => "John"
          }
        }
      })
      assert result1 == "John"
    end
  end

  describe "complex scenarios" do
    test "workflow node input preparation" do
      context = %{
        "$input" => %{
          "operation" => "send_notifications",
          "tenant_id" => "tenant_123"
        },
        "$nodes" => %{
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
        "$variables" => %{
          "api_base_url" => "https://api.example.com",
          "notification_template" => "Welcome {{name}}!"
        }
      }

      # Prepare input for notification node
      notification_input = %{
        "base_url" => "$variables.api_base_url",
        "tenant_id" => "$input.tenant_id",
        "template" => "$variables.notification_template",
        "first_email" => "$nodes.get_users.response.users[0].email",
        "second_email" => "$nodes.get_users.response.users[1].email",
        "first_user_id" => "$nodes.get_users.response.users[0].id"
      }

      {:ok, prepared} = Expression.process_map(notification_input, context)

      assert prepared == %{
               "base_url" => "https://api.example.com",
               "tenant_id" => "tenant_123",
               "template" => "Welcome {{name}}!",
               "first_email" => "john@test.com",
               "second_email" => "jane@test.com", 
               "first_user_id" => 1
             }
    end

    test "expression edge cases" do
      context = %{
        "$input" => %{
          "empty_list" => [],
          "null_value" => nil,
          "nested" => %{"deep" => %{"value" => "found"}}
        }
      }

      # Empty expressions should return as-is
      {:ok, "$"} = Expression.extract("$", context)

      # Deep nesting should work
      {:ok, value} = Expression.extract("$input.nested.deep.value", context)
      assert value == "found"

      # Accessing empty arrays should return nil for index access
      {:ok, empty} = Expression.extract("$input.empty_list[0]", context)
      assert empty == nil

      # Accessing nil should return nil (graceful handling)
      {:ok, result} = Expression.extract("$input.null_value.field", context)
      assert result == nil

      # Accessing missing root should return nil
      {:ok, result} = Expression.extract("$nonexistent.field", context)
      assert result == nil
    end
  end
end
