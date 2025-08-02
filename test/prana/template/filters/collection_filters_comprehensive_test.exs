defmodule Prana.Template.Filters.CollectionFiltersComprehensiveTest do
  use ExUnit.Case, async: false

  alias Prana.Template

  describe "collection filters - comprehensive tests" do
    setup do
      context = %{
        "$input" => %{
          "text" => "hello world",
          "items" => [1, 2, 3, 4, 5],
          "names" => ["alice", "bob", "charlie"],
          "mixed_list" => [1, "hello", 3, "world", 5],
          "nested_list" => [[1, 2], [3, 4], [5]],
          "numbers" => [10, 5, 8, 3, 12],
          "duplicates" => [1, 2, 2, 3, 1, 4, 3],
          "with_nils" => [1, nil, 2, nil, 3],
          "user_map" => %{"name" => "John", "age" => 30, "city" => "NYC"},
          "users" => [
            %{"name" => "Alice", "role" => "admin", "age" => 25},
            %{"name" => "Bob", "role" => "user", "age" => 30},
            %{"name" => "Charlie", "role" => "admin", "age" => 35}
          ],
          "empty_list" => [],
          "empty_string" => "",
          "empty_map" => %{}
        }
      }

      {:ok, context: context}
    end

    test "length filter with strings", %{context: context} do
      # String length
      assert {:ok, 11} = Template.render("{{ $input.text | length }}", context)
      assert {:ok, 0} = Template.render("{{ $input.empty_string | length }}", context)

      # Mixed template
      assert {:ok, "Length: 11"} = Template.render("Length: {{ $input.text | length }}", context)
    end

    test "length filter with lists", %{context: context} do
      # List length
      assert {:ok, 5} = Template.render("{{ $input.items | length }}", context)
      assert {:ok, 3} = Template.render("{{ $input.names | length }}", context)
      assert {:ok, 0} = Template.render("{{ $input.empty_list | length }}", context)

      # Mixed template
      assert {:ok, "Count: 5"} = Template.render("Count: {{ $input.items | length }}", context)
    end

    test "length filter with maps", %{context: context} do
      # Map size
      assert {:ok, 3} = Template.render("{{ $input.user_map | length }}", context)
      assert {:ok, 0} = Template.render("{{ $input.empty_map | length }}", context)

      # Mixed template
      assert {:ok, "Fields: 3"} = Template.render("Fields: {{ $input.user_map | length }}", context)
    end

    test "keys filter", %{context: context} do
      # Map keys
      assert {:ok, result} = Template.render("{{ $input.user_map | keys }}", context)
      assert is_list(result)
      assert length(result) == 3
      assert "name" in result
      assert "age" in result
      assert "city" in result

      # Empty map
      assert {:ok, []} = Template.render("{{ $input.empty_map | keys }}", context)
    end

    test "values filter", %{context: context} do
      # Map values
      assert {:ok, result} = Template.render("{{ $input.user_map | values }}", context)
      assert is_list(result)
      assert length(result) == 3
      assert "John" in result
      assert 30 in result
      assert "NYC" in result

      # Empty map
      assert {:ok, []} = Template.render("{{ $input.empty_map | values }}", context)
    end

    test "sort filter", %{context: context} do
      # Sort numbers
      assert {:ok, [3, 5, 8, 10, 12]} = Template.render("{{ $input.numbers | sort }}", context)

      # Sort strings
      assert {:ok, ["alice", "bob", "charlie"]} = Template.render("{{ $input.names | sort }}", context)

      # Empty list
      assert {:ok, []} = Template.render("{{ $input.empty_list | sort }}", context)

      # Mixed template with dump filter
      assert {:ok, "Sorted: [3, 5, 8, 10, 12]"} = Template.render("Sorted: {{ $input.numbers | sort | dump }}", context)
    end

    test "reverse filter with lists", %{context: context} do
      # Reverse list
      assert {:ok, [5, 4, 3, 2, 1]} = Template.render("{{ $input.items | reverse }}", context)
      assert {:ok, ["charlie", "bob", "alice"]} = Template.render("{{ $input.names | reverse }}", context)

      # Empty list
      assert {:ok, []} = Template.render("{{ $input.empty_list | reverse }}", context)
    end

    test "reverse filter with strings", %{context: context} do
      # Reverse string
      assert {:ok, "dlrow olleh"} = Template.render("{{ $input.text | reverse }}", context)
      assert {:ok, ""} = Template.render("{{ $input.empty_string | reverse }}", context)

      # Mixed template
      assert {:ok, "Reversed: dlrow olleh"} = Template.render("Reversed: {{ $input.text | reverse }}", context)
    end

    test "uniq filter", %{context: context} do
      # Remove duplicates
      assert {:ok, result} = Template.render("{{ $input.duplicates | uniq }}", context)
      assert length(result) == 4
      assert 1 in result
      assert 2 in result
      assert 3 in result
      assert 4 in result

      # No duplicates
      assert {:ok, [1, 2, 3, 4, 5]} = Template.render("{{ $input.items | uniq }}", context)

      # Empty list
      assert {:ok, []} = Template.render("{{ $input.empty_list | uniq }}", context)
    end

    test "slice filter with lists", %{context: context} do
      # Slice list
      assert {:ok, [2, 3, 4]} = Template.render("{{ $input.items | slice(1, 3) }}", context)
      assert {:ok, [1, 2]} = Template.render("{{ $input.items | slice(0, 2) }}", context)

      # Slice beyond bounds
      assert {:ok, [5]} = Template.render("{{ $input.items | slice(4, 5) }}", context)

      # Mixed template with dump filter
      assert {:ok, "Slice: [2, 3, 4]"} = Template.render("Slice: {{ $input.items | slice(1, 3) | dump }}", context)
    end

    test "slice filter with strings", %{context: context} do
      # Slice string
      assert {:ok, "ell"} = Template.render("{{ $input.text | slice(1, 3) }}", context)
      assert {:ok, "he"} = Template.render("{{ $input.text | slice(0, 2) }}", context)

      # Slice beyond bounds
      assert {:ok, "d"} = Template.render("{{ $input.text | slice(10, 5) }}", context)

      # Mixed template
      assert {:ok, "Part: ell"} = Template.render("Part: {{ $input.text | slice(1, 3) }}", context)
    end

    test "contains filter with lists", %{context: context} do
      # Contains element
      assert {:ok, true} = Template.render("{{ $input.items | contains(3) }}", context)
      assert {:ok, false} = Template.render("{{ $input.items | contains(10) }}", context)

      # Contains string
      assert {:ok, true} = Template.render("{{ $input.names | contains(\"bob\") }}", context)
      assert {:ok, false} = Template.render("{{ $input.names | contains(\"dave\") }}", context)
    end

    test "contains filter with strings", %{context: context} do
      # Contains substring
      assert {:ok, true} = Template.render("{{ $input.text | contains(\"world\") }}", context)
      assert {:ok, false} = Template.render("{{ $input.text | contains(\"xyz\") }}", context)

      # Mixed template
      assert {:ok, "Found: true"} = Template.render("Found: {{ $input.text | contains(\"world\") }}", context)
    end

    test "compact filter", %{context: context} do
      # Remove nils
      assert {:ok, [1, 2, 3]} = Template.render("{{ $input.with_nils | compact }}", context)

      # No nils
      assert {:ok, [1, 2, 3, 4, 5]} = Template.render("{{ $input.items | compact }}", context)

      # Empty list
      assert {:ok, []} = Template.render("{{ $input.empty_list | compact }}", context)

      # Mixed template with dump filter
      assert {:ok, "Clean: [1, 2, 3]"} = Template.render("Clean: {{ $input.with_nils | compact | dump }}", context)
    end

    test "flatten filter", %{context: context} do
      # Flatten nested list
      assert {:ok, [1, 2, 3, 4, 5]} = Template.render("{{ $input.nested_list | flatten }}", context)

      # Already flat
      assert {:ok, [1, 2, 3, 4, 5]} = Template.render("{{ $input.items | flatten }}", context)

      # Empty list
      assert {:ok, []} = Template.render("{{ $input.empty_list | flatten }}", context)

      # Mixed template with dump filter
      assert {:ok, "Flat: [1, 2, 3, 4, 5]"} = Template.render("Flat: {{ $input.nested_list | flatten | dump }}", context)
    end

    test "sum filter", %{context: context} do
      # Sum numbers
      assert {:ok, 15} = Template.render("{{ $input.items | sum }}", context)
      assert {:ok, 38} = Template.render("{{ $input.numbers | sum }}", context)

      # Sum with nils (should be filtered out)
      context_with_sum = Map.put(context, "$input", Map.put(context["$input"], "numbers_with_nil", [1, 2, nil, 3]))
      assert {:error, result} = Template.render("{{ $input.numbers_with_nil | sum }}", context_with_sum)
      assert String.contains?(result, "sum filter requires all elements to be numeric")

      # Empty list
      assert {:ok, 0} = Template.render("{{ $input.empty_list | sum }}", context)

      # Mixed template
      assert {:ok, "Total: 15"} = Template.render("Total: {{ $input.items | sum }}", context)
    end

    test "sum filter with string numbers", %{context: context} do
      # Mix of numbers and string numbers
      context_mixed = Map.put(context, "$input", Map.put(context["$input"], "mixed_numbers", [1, "2", 3.5, "4.5"]))
      assert {:ok, 11.0} = Template.render("{{ $input.mixed_numbers | sum }}", context_mixed)
    end

    test "group_by filter", %{context: context} do
      # Group users by role
      assert {:ok, result} = Template.render("{{ $input.users | group_by(\"role\") }}", context)
      assert is_map(result)
      assert Map.has_key?(result, "admin")
      assert Map.has_key?(result, "user")
      assert length(result["admin"]) == 2
      assert length(result["user"]) == 1

      # Group by age
      assert {:ok, result} = Template.render("{{ $input.users | group_by(\"age\") }}", context)
      assert is_map(result)
      assert Map.has_key?(result, 25)
      assert Map.has_key?(result, 30)
      assert Map.has_key?(result, 35)
    end

    test "map filter", %{context: context} do
      # Extract names
      assert {:ok, result} = Template.render("{{ $input.users | map(\"name\") }}", context)
      assert result == ["Alice", "Bob", "Charlie"]
      
      # Extract roles
      assert {:ok, result} = Template.render("{{ $input.users | map(\"role\") }}", context)
      assert result == ["admin", "user", "admin"]
      
      # Extract ages
      assert {:ok, result} = Template.render("{{ $input.users | map(\"age\") }}", context)
      assert result == [25, 30, 35]
      
      # Mixed template with map filter
      assert {:ok, "Names: [\"Alice\", \"Bob\", \"Charlie\"]"} = 
        Template.render("Names: {{ $input.users | map(\"name\") | dump }}", context)
    end

    test "filter filter", %{context: context} do
      # Filter by role
      assert {:ok, result} = Template.render("{{ $input.users | filter(\"role\", \"admin\") }}", context)
      assert length(result) == 2
      assert Enum.all?(result, fn user -> user["role"] == "admin" end)
      
      # Filter by age
      assert {:ok, result} = Template.render("{{ $input.users | filter(\"age\", 30) }}", context)
      assert length(result) == 1
      assert hd(result)["name"] == "Bob"
      
      # Filter with no matches
      assert {:ok, result} = Template.render("{{ $input.users | filter(\"role\", \"guest\") }}", context)
      assert result == []
      
      # Mixed template with filter
      assert {:ok, result} = Template.render("Admins: {{ $input.users | filter(\"role\", \"admin\") | map(\"name\") | join(\", \") }}", context)
      assert result == "Admins: Alice, Charlie"
    end

    test "reject filter", %{context: context} do
      # Reject by role
      assert {:ok, result} = Template.render("{{ $input.users | reject(\"role\", \"admin\") }}", context)
      assert length(result) == 1
      assert hd(result)["role"] == "user"
      assert hd(result)["name"] == "Bob"
      
      # Reject by age
      assert {:ok, result} = Template.render("{{ $input.users | reject(\"age\", 30) }}", context)
      assert length(result) == 2
      assert Enum.all?(result, fn user -> user["age"] != 30 end)
      
      # Reject with no matches (returns all)
      assert {:ok, result} = Template.render("{{ $input.users | reject(\"role\", \"guest\") }}", context)
      assert length(result) == 3
      
      # Mixed template with reject
      assert {:ok, result} = Template.render("Non-admins: {{ $input.users | reject(\"role\", \"admin\") | map(\"name\") | join(\", \") }}", context)
      assert result == "Non-admins: Bob"
    end

    test "chained data filters", %{context: context} do
      # Chain: sort then reverse
      assert {:ok, [12, 10, 8, 5, 3]} = Template.render("{{ $input.numbers | sort | reverse }}", context)

      # Chain: uniq then sort
      assert {:ok, [1, 2, 3, 4]} = Template.render("{{ $input.duplicates | uniq | sort }}", context)

      # Chain: compact then sum
      assert {:ok, 6} = Template.render("{{ $input.with_nils | compact | sum }}", context)

      # Complex chain
      assert {:ok, 4} = Template.render("{{ $input.duplicates | uniq | sort | length }}", context)
    end

    test "data filters with collection operations", %{context: context} do
      # Use data filters with collection filters
      assert {:ok, "3, 5, 8, 10, 12"} = Template.render("{{ $input.numbers | sort | join(\", \") }}", context)

      # Use with string filters
      assert {:ok, "ALICE, BOB, CHARLIE"} =
               Template.render("{{ $input.names | sort | join(\", \") | upper_case }}", context)
    end

    test "type preservation in pure expressions", %{context: context} do
      # Pure data expressions should return proper types
      assert {:ok, result} = Template.render("{{ $input.items | length }}", context)
      assert result == 5
      assert is_integer(result)

      assert {:ok, result} = Template.render("{{ $input.names | sort }}", context)
      assert is_list(result)

      assert {:ok, result} = Template.render("{{ $input.text | contains(\"world\") }}", context)
      assert result == true
      assert is_boolean(result)
    end

    test "mixed content returns string", %{context: context} do
      # Mixed content should always return string
      assert {:ok, result} = Template.render("Size: {{ $input.items | length }}", context)
      assert result == "Size: 5"
      assert is_binary(result)
    end

    test "error handling for invalid operations", %{context: context} do
      # Length filter with number (invalid)
      assert {:error, result} = Template.render("{{ 42 | length }}", context)
      assert String.contains?(result, "length filter only works on lists, strings, and maps")

      # Keys filter with list (invalid)
      assert {:error, result} = Template.render("{{ $input.items | keys }}", context)
      assert String.contains?(result, "keys filter only supports maps")

      # Sort filter with string (invalid)
      assert {:error, result} = Template.render("{{ $input.text | sort }}", context)
      assert String.contains?(result, "sort filter only supports lists")
    end

    test "edge cases with empty collections", %{context: context} do
      # Operations on empty collections
      assert {:ok, []} = Template.render("{{ $input.empty_list | sort }}", context)
      assert {:ok, []} = Template.render("{{ $input.empty_list | reverse }}", context)
      assert {:ok, []} = Template.render("{{ $input.empty_list | uniq }}", context)
      assert {:ok, 0} = Template.render("{{ $input.empty_list | sum }}", context)
      assert {:ok, 0} = Template.render("{{ $input.empty_string | length }}", context)
    end

    test "dump filter", %{context: context} do
      # Dump list
      assert {:ok, "[1, 2, 3, 4, 5]"} = Template.render("{{ $input.items | dump }}", context)
      
      # Dump map
      assert {:ok, result} = Template.render("{{ $input.user_map | dump }}", context)
      assert String.contains?(result, "name")
      assert String.contains?(result, "John")
      
      # Dump string (should return as-is)
      assert {:ok, "hello world"} = Template.render("{{ $input.text | dump }}", context)
      
      # Mixed template with dump
      assert {:ok, "Data: [1, 2, 3, 4, 5]"} = Template.render("Data: {{ $input.items | dump }}", context)
    end

    test "complex data transformations", %{context: context} do
      # Extract and transform user data
      template = ~s[{{ $input.users | group_by("role") | keys | sort | join(", ") }}]
      assert {:ok, "admin, user"} = Template.render(template, context)

      # Extract names and join
      template2 = ~s[{{ $input.users | map("name") | join(", ") }}]
      assert {:ok, "Alice, Bob, Charlie"} = Template.render(template2, context)

      # Filter and extract admin names
      template3 = ~s[{{ $input.users | filter("role", "admin") | map("name") | join(" & ") }}]
      assert {:ok, "Alice & Charlie"} = Template.render(template3, context)

      # Reject admins and get average age of non-admins
      template4 = ~s[{{ $input.users | reject("role", "admin") | map("age") | sum }}]
      assert {:ok, 30} = Template.render(template4, context)

      # Statistical operations
      template5 = "{{ $input.numbers | sort | slice(0, 3) | sum }}"
      # 3 + 5 + 8 = 16
      assert {:ok, 16} = Template.render(template5, context)
    end
  end
end
