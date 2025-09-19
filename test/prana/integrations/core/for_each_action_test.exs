defmodule Prana.Integrations.Core.ForEachActionTest do
  @moduledoc """
  Comprehensive unit tests for For Each Loop action.

  Tests cover:
  - Single mode iterations with context management
  - Batch mode iterations with optimized processing
  - Loopback detection and state management
  - Parameter validation using Skema
  - Error handling scenarios
  - Edge cases (empty collections, single items, etc.)
  """

  use ExUnit.Case, async: true

  alias Prana.Integrations.Core.ForEachAction

  describe "specification/0" do
    test "returns correct action definition" do
      spec = ForEachAction.definition()

      assert spec.name == "core.for_each"
      assert spec.display_name == "For Each"
      assert spec.type == :action
      assert spec.input_ports == ["main"]
      assert spec.output_ports == ["loop", "done", "error"]
    end
  end

  describe "validate_params/1" do
    test "validates single mode parameters" do
      params = %{"collection" => [1, 2, 3], "mode" => "single"}

      assert {:ok, validated} = ForEachAction.validate_params(params)
      assert validated.collection == [1, 2, 3]
      assert validated.mode == "single"
    end

    test "validates batch mode parameters with batch_size" do
      params = %{"collection" => [1, 2, 3, 4, 5], "mode" => "batch", "batch_size" => 2}

      assert {:ok, validated} = ForEachAction.validate_params(params)
      assert validated.collection == [1, 2, 3, 4, 5]
      assert validated.mode == "batch"
      assert validated.batch_size == 2
    end

    test "rejects missing collection" do
      params = %{"mode" => "single"}

      assert {:error, error} = ForEachAction.validate_params(params)
      assert error.code == "validation_error"
    end

    test "rejects missing mode" do
      params = %{"collection" => [1, 2, 3]}

      assert {:error, error} = ForEachAction.validate_params(params)
      assert error.code == "validation_error"
    end

    test "rejects invalid mode" do
      params = %{"collection" => [1, 2, 3], "mode" => "invalid"}

      assert {:error, error} = ForEachAction.validate_params(params)
      assert error.code == "validation_error"
    end

    test "rejects batch mode without batch_size" do
      params = %{"collection" => [1, 2, 3], "mode" => "batch"}

      assert {:error, error} = ForEachAction.validate_params(params)
      assert error.code == "validation_error"
    end

    test "rejects invalid batch_size" do
      params = %{"collection" => [1, 2, 3], "mode" => "batch", "batch_size" => 0}

      assert {:error, error} = ForEachAction.validate_params(params)
      assert error.code == "validation_error"
    end
  end

  describe "execute/2 - single mode" do
    test "starts new loop with first item from collection" do
      params = %{"collection" => [1, 2, 3], "mode" => "single"}

      context = %{
        "$execution" => %{
          "current_node_key" => "loop_node",
          "loopback" => false
        },
        "$context" => %{"run_index" => 0},
        "$nodes" => %{}
      }

      assert {:ok, output_data, "loop", %{"node_context" => node_context}} =
               ForEachAction.execute(params, context)

      # First item should be returned
      assert output_data == 1

      # Context should be set up for next iteration
      assert node_context["item_count"] == 3
      assert node_context["remaining_items"] == [2, 3]
      assert node_context["current_loop_index"] == 0
      assert node_context["current_run_index"] == 0
      assert node_context["has_more_item"] == true
    end

    test "continues loop with remaining items" do
      params = %{"collection" => [1, 2, 3], "mode" => "single"}

      # Simulate context from previous iteration
      node_context = %{
        "item_count" => 3,
        "remaining_items" => [2, 3],
        "current_loop_index" => 0,
        "current_run_index" => 0,
        "has_more_item" => true
      }

      context = %{
        "$execution" => %{
          "current_node_key" => "loop_node",
          "loopback" => true
        },
        "$nodes" => %{
          "loop_node" => %{"context" => node_context}
        }
      }

      assert {:ok, output_data, "loop", %{"node_context" => updated_context}} =
               ForEachAction.execute(params, context)

      # Second item should be returned
      assert output_data == 2

      # Context should be updated
      assert updated_context["remaining_items"] == [3]
      assert updated_context["current_loop_index"] == 1
      assert updated_context["current_run_index"] == 1
      # Last item coming next
      assert updated_context["has_more_item"] == true
    end

    test "processes last item with has_more_item = false" do
      params = %{"collection" => [1, 2, 3], "mode" => "single"}

      # Context for last item
      node_context = %{
        "item_count" => 3,
        "remaining_items" => [3],
        "current_loop_index" => 1,
        "current_run_index" => 1,
        "has_more_item" => false
      }

      context = %{
        "$execution" => %{
          "current_node_key" => "loop_node",
          "loopback" => true
        },
        "$nodes" => %{
          "loop_node" => %{"context" => node_context}
        }
      }

      assert {:ok, output_data, "loop", %{"node_context" => updated_context}} =
               ForEachAction.execute(params, context)

      # Last item should be returned
      assert output_data == 3

      # Context should show completion
      assert updated_context["remaining_items"] == []
      assert updated_context["current_loop_index"] == 2
      assert updated_context["current_run_index"] == 2
      assert updated_context["has_more_item"] == false
    end

    test "completes loop when no remaining items" do
      params = %{"collection" => [1, 2, 3], "mode" => "single"}

      # Context after all items processed
      node_context = %{
        "item_count" => 3,
        "remaining_items" => [],
        "current_loop_index" => 2,
        "current_run_index" => 2,
        "has_more_item" => false
      }

      context = %{
        "$execution" => %{
          "current_node_key" => "loop_node",
          "loopback" => true
        },
        "$nodes" => %{
          "loop_node" => %{"context" => node_context}
        }
      }

      assert {:ok, %{}, "done"} = ForEachAction.execute(params, context)
    end

    test "handles single item collection correctly" do
      params = %{"collection" => ["only_item"], "mode" => "single"}

      context = %{
        "$execution" => %{
          "current_node_key" => "loop_node",
          "loopback" => false
        },
        "$context" => %{"run_index" => 0},
        "$nodes" => %{}
      }

      assert {:ok, output_data, "loop", %{"node_context" => node_context}} =
               ForEachAction.execute(params, context)

      # Single item should be returned
      assert output_data == "only_item"

      # Context should indicate no more items
      assert node_context["item_count"] == 1
      assert node_context["remaining_items"] == []
      assert node_context["current_loop_index"] == 0
      assert node_context["current_run_index"] == 0
      assert node_context["has_more_item"] == false
    end
  end

  describe "execute/2 - batch mode" do
    test "starts new loop with first batch" do
      params = %{"collection" => [1, 2, 3, 4, 5], "mode" => "batch", "batch_size" => 2}

      context = %{
        "$execution" => %{
          "current_node_key" => "loop_node",
          "loopback" => false
        },
        "$context" => %{"run_index" => 0},
        "$nodes" => %{}
      }

      assert {:ok, output_data, "loop", %{"node_context" => node_context}} =
               ForEachAction.execute(params, context)

      # First batch should be returned
      assert output_data == [1, 2]

      # Context should be set up for next iteration
      assert node_context["item_count"] == 5
      assert node_context["remaining_items"] == [3, 4, 5]
      assert node_context["current_loop_index"] == 0
      assert node_context["current_run_index"] == 0
      assert node_context["has_more_item"] == true
    end

    test "continues with next batch" do
      params = %{"collection" => [1, 2, 3, 4, 5], "mode" => "batch", "batch_size" => 2}

      # Context from previous batch iteration
      node_context = %{
        "item_count" => 5,
        "remaining_items" => [3, 4, 5],
        "current_loop_index" => 0,
        "current_run_index" => 0,
        "has_more_item" => true
      }

      context = %{
        "$execution" => %{
          "current_node_key" => "loop_node",
          "loopback" => true
        },
        "$nodes" => %{
          "loop_node" => %{"context" => node_context}
        }
      }

      assert {:ok, output_data, "loop", %{"node_context" => updated_context}} =
               ForEachAction.execute(params, context)

      # Next batch should be returned
      assert output_data == [3, 4]

      # Context should be updated
      assert updated_context["remaining_items"] == [5]
      assert updated_context["current_loop_index"] == 1
      assert updated_context["current_run_index"] == 1
      # Last batch coming next
      assert updated_context["has_more_item"] == true
    end

    test "processes final partial batch" do
      params = %{"collection" => [1, 2, 3, 4, 5], "mode" => "batch", "batch_size" => 2}

      # Context for final partial batch
      node_context = %{
        "item_count" => 5,
        "remaining_items" => [5],
        "current_loop_index" => 1,
        "current_run_index" => 1,
        "has_more_item" => false
      }

      context = %{
        "$execution" => %{
          "current_node_key" => "loop_node",
          "loopback" => true
        },
        "$nodes" => %{
          "loop_node" => %{"context" => node_context}
        }
      }

      assert {:ok, output_data, "loop", %{"node_context" => updated_context}} =
               ForEachAction.execute(params, context)

      # Final partial batch should be returned
      assert output_data == [5]

      # Context should show completion
      assert updated_context["remaining_items"] == []
      assert updated_context["current_loop_index"] == 2
      assert updated_context["current_run_index"] == 2
      assert updated_context["has_more_item"] == false
    end

    test "handles exact batch size division" do
      params = %{"collection" => [1, 2, 3, 4], "mode" => "batch", "batch_size" => 2}

      context = %{
        "$execution" => %{
          "current_node_key" => "loop_node",
          "loopback" => false
        },
        "$context" => %{"run_index" => 0},
        "$nodes" => %{
          "loop_node" => %{"context" => %{}}
        }
      }

      # First batch
      assert {:ok, [1, 2], "loop", %{"node_context" => context1}} =
               ForEachAction.execute(params, context)

      assert context1["has_more_item"] == true

      # Second batch
      context_with_state = put_in(context, ["$nodes", "loop_node", "context"], context1)
      context_with_loopback = put_in(context_with_state, ["$execution", "loopback"], true)

      assert {:ok, [3, 4], "loop", %{"node_context" => context2}} =
               ForEachAction.execute(params, context_with_loopback)

      assert context2["has_more_item"] == false
      assert context2["remaining_items"] == []

      # Should complete on next call
      final_context = put_in(context_with_loopback, ["$nodes", "loop_node", "context"], context2)
      assert {:ok, %{}, "done"} = ForEachAction.execute(params, final_context)
    end
  end

  describe "execute/2 - error handling" do
    test "handles invalid collection type" do
      params = %{"collection" => "not_a_list", "mode" => "single"}

      context = %{
        "$execution" => %{
          "current_node_key" => "loop_node",
          "loopback" => false
        },
        "$context" => %{"run_index" => 0},
        "$nodes" => %{}
      }

      assert {:error, %{code: "invalid_collection_type"}} = ForEachAction.execute(params, context)
    end

    test "handles empty collection" do
      params = %{"collection" => [], "mode" => "single"}

      context = %{
        "$execution" => %{
          "current_node_key" => "loop_node",
          "loopback" => false
        },
        "$context" => %{"run_index" => 0},
        "$nodes" => %{}
      }

      # Empty collection should fail with empty_collection error
      assert {:ok, %{}, "done"} = ForEachAction.execute(params, context)
    end

    test "handles corrupted context on loopback" do
      params = %{"collection" => [1, 2, 3], "mode" => "single"}

      context = %{
        "$execution" => %{
          "current_node_key" => "loop_node",
          "loopback" => true
        },
        "$nodes" => %{
          # Missing required context fields
          "loop_node" => %{"context" => %{}}
        }
      }

      assert {:error,
              %Prana.Core.Error{code: "invalid_loopback", details: nil, message: "Loopback context is invalid or missing"}} =
               ForEachAction.execute(params, context)
    end
  end

  describe "execute/2 - edge cases" do
    test "handles very large batch sizes" do
      collection = Enum.to_list(1..10)
      params = %{"collection" => collection, "mode" => "batch", "batch_size" => 100}

      context = %{
        "$execution" => %{
          "current_node_key" => "loop_node",
          "loopback" => false
        },
        "$context" => %{"run_index" => 0},
        "$nodes" => %{}
      }

      assert {:ok, output_data, "loop", %{"node_context" => node_context}} =
               ForEachAction.execute(params, context)

      # Should return entire collection as single batch
      assert output_data == collection
      assert node_context["remaining_items"] == []
      assert node_context["has_more_item"] == false
    end

    test "handles batch_size of 1 (equivalent to single mode)" do
      params = %{"collection" => [1, 2, 3], "mode" => "batch", "batch_size" => 1}

      context = %{
        "$execution" => %{
          "current_node_key" => "loop_node",
          "loopback" => false
        },
        "$context" => %{"run_index" => 0},
        "$nodes" => %{}
      }

      assert {:ok, output_data, "loop", %{"node_context" => node_context}} =
               ForEachAction.execute(params, context)

      # Should return single item in array format
      assert output_data == [1]
      assert node_context["remaining_items"] == [2, 3]
      assert node_context["has_more_item"] == true
    end

    test "maintains separate contexts for different node keys" do
      params1 = %{"collection" => [1, 2], "mode" => "single"}
      params2 = %{"collection" => ["a", "b"], "mode" => "single"}

      # First loop node
      context1 = %{
        "$execution" => %{
          "current_node_key" => "loop_node_1",
          "loopback" => false
        },
        "$context" => %{"run_index" => 0},
        "$nodes" => %{}
      }

      # Second loop node
      context2 = %{
        "$execution" => %{
          "current_node_key" => "loop_node_2",
          "loopback" => false
        },
        "$context" => %{"run_index" => 0},
        "$nodes" => %{}
      }

      # Both should work independently
      assert {:ok, 1, "loop", %{"node_context" => context_1}} = ForEachAction.execute(params1, context1)
      assert {:ok, "a", "loop", %{"node_context" => context_2}} = ForEachAction.execute(params2, context2)

      assert context_1["item_count"] == 2
      assert context_2["item_count"] == 2
      assert context_1["remaining_items"] == [2]
      assert context_2["remaining_items"] == ["b"]
    end
  end
end
