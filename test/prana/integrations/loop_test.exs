defmodule Prana.Integrations.LoopTest do
  @moduledoc """
  Comprehensive unit tests for Loop integration, focusing on for_each action.

  Tests cover:
  - Single mode iterations
  - Batch mode iterations  
  - Context management and optimization
  - Loopback detection
  - Error handling scenarios
  - Edge cases (empty collections, single items, etc.)
  """

  use ExUnit.Case, async: true

  alias Prana.Integrations.Loop

  describe "integration definition" do
    test "provides correct integration metadata" do
      definition = Loop.definition()

      assert definition.name == "loop"
      assert definition.display_name == "Loop"
      assert definition.category == "control"
      assert definition.version == "1.0.0"
      assert is_map(definition.actions)
      assert Map.has_key?(definition.actions, "for_each")
    end

    test "for_each action has correct configuration" do
      definition = Loop.definition()
      for_each_action = definition.actions["for_each"]

      assert for_each_action.name == "loop.for_each"
      assert for_each_action.module == Loop
      assert for_each_action.function == :for_each
      assert for_each_action.input_ports == ["main"]
      assert for_each_action.output_ports == ["loop", "done"]
    end
  end

  describe "for_each action - single mode" do
    test "starts new loop with single item from collection" do
      params = %{"collection" => [1, 2, 3], "mode" => "single"}
      
      context = %{
        "$execution" => %{
          "current_node_key" => "loop_node",
          "loopback" => false
        },
        "$nodes" => %{}
      }

      assert {:ok, output_data, "loop", %{"node_context" => node_context}} = Loop.for_each(params, context)

      # First item should be returned
      assert output_data == 1

      # Context should be set up for next iteration
      assert node_context["collection"] == [1, 2, 3]
      assert node_context["item_count"] == 3
      assert node_context["remaining_items"] == [2, 3]
      assert node_context["current_loop_index"] == 1
      assert node_context["current_run_index"] == 0
      assert node_context["has_more_item"] == true
    end

    test "continues loop with remaining items" do
      params = %{"collection" => [1, 2, 3], "mode" => "single"}
      
      # Simulate context from previous iteration
      node_context = %{
        "collection" => [1, 2, 3],
        "item_count" => 3,
        "remaining_items" => [2, 3],
        "current_loop_index" => 1,
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

      assert {:ok, output_data, "loop", %{"node_context" => updated_context}} = Loop.for_each(params, context)

      # Second item should be returned
      assert output_data == 2

      # Context should be updated
      assert updated_context["remaining_items"] == [3]
      assert updated_context["current_loop_index"] == 2
      assert updated_context["current_run_index"] == 1
      assert updated_context["has_more_item"] == false  # Last item coming next
    end

    test "processes last item with has_more_item = false" do
      params = %{"collection" => [1, 2, 3], "mode" => "single"}
      
      # Context for last item
      node_context = %{
        "collection" => [1, 2, 3],
        "item_count" => 3,
        "remaining_items" => [3],
        "current_loop_index" => 2,
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

      assert {:ok, output_data, "loop", %{"node_context" => updated_context}} = Loop.for_each(params, context)

      # Last item should be returned
      assert output_data == 3

      # Context should show completion
      assert updated_context["remaining_items"] == []
      assert updated_context["current_loop_index"] == 3
      assert updated_context["current_run_index"] == 2
      assert updated_context["has_more_item"] == false
    end

    test "completes loop when no remaining items" do
      params = %{"collection" => [1, 2, 3], "mode" => "single"}
      
      # Context after all items processed
      node_context = %{
        "collection" => [1, 2, 3],
        "item_count" => 3,
        "remaining_items" => [],
        "current_loop_index" => 3,
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

      assert {:ok, %{}, "done"} = Loop.for_each(params, context)
    end

    test "handles single item collection correctly" do
      params = %{"collection" => ["only_item"], "mode" => "single"}
      
      context = %{
        "$execution" => %{
          "current_node_key" => "loop_node",
          "loopback" => false
        },
        "$nodes" => %{}
      }

      assert {:ok, output_data, "loop", %{"node_context" => node_context}} = Loop.for_each(params, context)

      # Single item should be returned
      assert output_data == "only_item"

      # Context should indicate no more items
      assert node_context["collection"] == ["only_item"]
      assert node_context["item_count"] == 1
      assert node_context["remaining_items"] == []
      assert node_context["current_loop_index"] == 1
      assert node_context["current_run_index"] == 0
      assert node_context["has_more_item"] == false
    end
  end

  describe "for_each action - batch mode" do
    test "starts new loop with first batch" do
      params = %{"collection" => [1, 2, 3, 4, 5], "mode" => "batch", "batch_size" => 2}
      
      context = %{
        "$execution" => %{
          "current_node_key" => "loop_node",
          "loopback" => false
        },
        "$nodes" => %{}
      }

      assert {:ok, output_data, "loop", %{"node_context" => node_context}} = Loop.for_each(params, context)

      # First batch should be returned
      assert output_data == [1, 2]

      # Context should be set up for next iteration
      assert node_context["collection"] == [1, 2, 3, 4, 5]
      assert node_context["item_count"] == 5
      assert node_context["remaining_items"] == [3, 4, 5]
      assert node_context["current_loop_index"] == 2
      assert node_context["current_run_index"] == 0
      assert node_context["has_more_item"] == true
    end

    test "continues with next batch" do
      params = %{"collection" => [1, 2, 3, 4, 5], "mode" => "batch", "batch_size" => 2}
      
      # Context from previous batch iteration
      node_context = %{
        "collection" => [1, 2, 3, 4, 5],
        "item_count" => 5,
        "remaining_items" => [3, 4, 5],
        "current_loop_index" => 2,
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

      assert {:ok, output_data, "loop", %{"node_context" => updated_context}} = Loop.for_each(params, context)

      # Next batch should be returned
      assert output_data == [3, 4]

      # Context should be updated
      assert updated_context["remaining_items"] == [5]
      assert updated_context["current_loop_index"] == 4
      assert updated_context["current_run_index"] == 1
      assert updated_context["has_more_item"] == false  # Last batch coming next
    end

    test "processes final partial batch" do
      params = %{"collection" => [1, 2, 3, 4, 5], "mode" => "batch", "batch_size" => 2}
      
      # Context for final partial batch
      node_context = %{
        "collection" => [1, 2, 3, 4, 5],
        "item_count" => 5,
        "remaining_items" => [5],
        "current_loop_index" => 4,
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

      assert {:ok, output_data, "loop", %{"node_context" => updated_context}} = Loop.for_each(params, context)

      # Final partial batch should be returned
      assert output_data == [5]

      # Context should show completion
      assert updated_context["remaining_items"] == []
      assert updated_context["current_loop_index"] == 5
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
        "$nodes" => %{}
      }

      # First batch
      assert {:ok, [1, 2], "loop", %{"node_context" => context1}} = Loop.for_each(params, context)
      assert context1["has_more_item"] == true

      # Second batch 
      context_with_state = put_in(context, ["$nodes", "loop_node", "context"], context1)
      context_with_loopback = put_in(context_with_state, ["$execution", "loopback"], true)
      
      assert {:ok, [3, 4], "loop", %{"node_context" => context2}} = Loop.for_each(params, context_with_loopback)
      assert context2["has_more_item"] == false
      assert context2["remaining_items"] == []

      # Should complete on next call
      final_context = put_in(context_with_loopback, ["$nodes", "loop_node", "context"], context2)
      assert {:ok, %{}, "done"} = Loop.for_each(params, final_context)
    end
  end

  describe "for_each action - expression evaluation" do
    test "evaluates collection expression from context" do
      params = %{"collection" => "{{$input.items}}", "mode" => "single"}
      
      context = %{
        "$input" => %{"items" => ["a", "b", "c"]},
        "$execution" => %{
          "current_node_key" => "loop_node",
          "loopback" => false
        },
        "$nodes" => %{}
      }

      assert {:ok, output_data, "loop", %{"node_context" => node_context}} = Loop.for_each(params, context)

      assert output_data == "a"
      assert node_context["collection"] == ["a", "b", "c"]
      assert node_context["remaining_items"] == ["b", "c"]
    end

    test "evaluates complex expressions" do
      params = %{"collection" => "{{$nodes.data_node.output.users}}", "mode" => "single"}
      
      context = %{
        "$nodes" => %{
          "data_node" => %{
            "output" => %{"users" => [%{"id" => 1}, %{"id" => 2}]}
          }
        },
        "$execution" => %{
          "current_node_key" => "loop_node",
          "loopback" => false
        }
      }

      assert {:ok, output_data, "loop", %{"node_context" => node_context}} = Loop.for_each(params, context)

      assert output_data == %{"id" => 1}
      assert node_context["collection"] == [%{"id" => 1}, %{"id" => 2}]
    end
  end

  describe "for_each action - error handling" do
    test "handles missing collection parameter" do
      params = %{"mode" => "single"}
      
      context = %{
        "$execution" => %{
          "current_node_key" => "loop_node",
          "loopback" => false
        },
        "$nodes" => %{}
      }

      assert {:error, %{code: "missing_collection"}} = Loop.for_each(params, context)
    end

    test "handles invalid collection type" do
      params = %{"collection" => "not_a_list", "mode" => "single"}
      
      context = %{
        "$execution" => %{
          "current_node_key" => "loop_node",
          "loopback" => false
        },
        "$nodes" => %{}
      }

      assert {:error, %{code: "invalid_collection_type"}} = Loop.for_each(params, context)
    end

    test "handles empty collection" do
      params = %{"collection" => [], "mode" => "single"}
      
      context = %{
        "$execution" => %{
          "current_node_key" => "loop_node",
          "loopback" => false
        },
        "$nodes" => %{}
      }

      assert {:error, %{code: "empty_collection"}} = Loop.for_each(params, context)
    end

    test "handles missing mode parameter" do
      params = %{"collection" => [1, 2, 3]}
      
      context = %{
        "$execution" => %{
          "current_node_key" => "loop_node",
          "loopback" => false
        },
        "$nodes" => %{}
      }

      assert {:error, %{code: "missing_mode"}} = Loop.for_each(params, context)
    end

    test "handles invalid mode" do
      params = %{"collection" => [1, 2, 3], "mode" => "invalid_mode"}
      
      context = %{
        "$execution" => %{
          "current_node_key" => "loop_node",
          "loopback" => false
        },
        "$nodes" => %{}
      }

      assert {:error, %{code: "invalid_mode"}} = Loop.for_each(params, context)
    end

    test "handles missing batch_size for batch mode" do
      params = %{"collection" => [1, 2, 3], "mode" => "batch"}
      
      context = %{
        "$execution" => %{
          "current_node_key" => "loop_node",
          "loopback" => false
        },
        "$nodes" => %{}
      }

      assert {:error, %{code: "missing_batch_size"}} = Loop.for_each(params, context)
    end

    test "handles invalid batch_size values" do
      params = %{"collection" => [1, 2, 3], "mode" => "batch", "batch_size" => 0}
      
      context = %{
        "$execution" => %{
          "current_node_key" => "loop_node",
          "loopback" => false
        },
        "$nodes" => %{}
      }

      assert {:error, %{code: "missing_batch_size"}} = Loop.for_each(params, context)
    end

    test "handles corrupted context on loopback" do
      params = %{"collection" => [1, 2, 3], "mode" => "single"}
      
      context = %{
        "$execution" => %{
          "current_node_key" => "loop_node",
          "loopback" => true
        },
        "$nodes" => %{
          "loop_node" => %{"context" => %{}} # Missing required context fields
        }
      }

      assert {:error, "Loop context missing or corrupted on loopback execution"} = Loop.for_each(params, context)
    end

    test "handles expression evaluation errors" do
      params = %{"collection" => "{{$invalid.path}}", "mode" => "single"}
      
      context = %{
        "$execution" => %{
          "current_node_key" => "loop_node",
          "loopback" => false
        },
        "$nodes" => %{}
      }

      assert {:error, %{code: "collection_evaluation_failed"}} = Loop.for_each(params, context)
    end
  end

  describe "for_each action - edge cases" do
    test "handles very large batch sizes" do
      collection = Enum.to_list(1..10)
      params = %{"collection" => collection, "mode" => "batch", "batch_size" => 100}
      
      context = %{
        "$execution" => %{
          "current_node_key" => "loop_node",
          "loopback" => false
        },
        "$nodes" => %{}
      }

      assert {:ok, output_data, "loop", %{"node_context" => node_context}} = Loop.for_each(params, context)

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
        "$nodes" => %{}
      }

      assert {:ok, output_data, "loop", %{"node_context" => node_context}} = Loop.for_each(params, context)

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
        "$nodes" => %{}
      }

      # Second loop node  
      context2 = %{
        "$execution" => %{
          "current_node_key" => "loop_node_2",
          "loopback" => false
        },
        "$nodes" => %{}
      }

      # Both should work independently
      assert {:ok, 1, "loop", %{"node_context" => context_1}} = Loop.for_each(params1, context1)
      assert {:ok, "a", "loop", %{"node_context" => context_2}} = Loop.for_each(params2, context2)

      assert context_1["collection"] == [1, 2]
      assert context_2["collection"] == ["a", "b"]
    end
  end

  describe "resume action" do
    test "handles resume with data" do
      resume_data = %{"result" => "resumed"}
      
      assert {:ok, resume_data, "done"} = Loop.resume(%{}, %{}, resume_data)
    end
  end
end