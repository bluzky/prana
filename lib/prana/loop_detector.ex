defmodule Prana.LoopDetector do
  @moduledoc """
  Detects loops in workflows using Tarjan's strongly connected components algorithm.

  Provides loop detection and node annotation capabilities for workflow graphs.
  Supports:
  - Simple loops (A → B → C → B)
  - Self-loops (A → A) 
  - Nested loops with hierarchy detection
  - Multiple disconnected loops

  ## Loop Metadata Structure

  Nodes are annotated with metadata containing:
  - `loop_level`: Nesting depth (0 = no loop, 1 = outer, 2+ = nested)
  - `loop_role`: `:start_loop`, `:in_loop`, or `:end_loop` 
  - `loop_ids`: Array of loop identifiers the node belongs to

  ## Example

      workflow = %Workflow{nodes: [...], connections: %{...}}
      annotated_workflow = LoopDetector.detect_and_annotate(workflow)
      
      # Check node loop metadata
      node = Enum.find(annotated_workflow.nodes, &(&1.key == "loop_node"))
      node.metadata[:loop_level]  # => 1
      node.metadata[:loop_role]   # => :start_loop
      node.metadata[:loop_ids]    # => ["loop_1"]
  """

  alias Prana.Workflow

  @doc """
  Detect loops in a workflow and annotate nodes with loop metadata.

  Uses Tarjan's strongly connected components algorithm to efficiently
  find all loops, then builds a hierarchy for nested loops and annotates
  each node with comprehensive loop information.

  ## Parameters
  - `workflow` - The workflow to analyze

  ## Returns
  - `Workflow.t()` - Workflow with nodes annotated with loop metadata
  """
  @spec detect_and_annotate(Workflow.t()) :: Workflow.t()
  def detect_and_annotate(%Workflow{} = workflow) do
    # Find all strongly connected components (SCCs)
    sccs = find_strongly_connected_components(workflow)

    # Filter SCCs that represent actual loops (size > 1 or self-loop)
    loops = filter_loops(sccs, workflow)

    # Build nesting hierarchy for nested loops
    loop_hierarchy = build_loop_hierarchy(loops)

    # Annotate nodes with loop metadata
    annotated_nodes = annotate_nodes_with_loop_info(workflow.nodes, loop_hierarchy)

    %{workflow | nodes: annotated_nodes}
  end

  # ============================================================================
  # Tarjan's Strongly Connected Components Algorithm
  # ============================================================================

  # Find all strongly connected components using Tarjan's algorithm
  @spec find_strongly_connected_components(Workflow.t()) :: [MapSet.t()]
  defp find_strongly_connected_components(%Workflow{} = workflow) do
    state = %{
      index: 0,
      stack: [],
      indices: %{},
      lowlinks: %{},
      on_stack: MapSet.new(),
      sccs: []
    }

    workflow.nodes
    |> Enum.reduce(state, fn node, acc ->
      if Map.has_key?(acc.indices, node.key) do
        acc
      else
        tarjan_strongconnect(workflow, node.key, acc)
      end
    end)
    |> Map.get(:sccs)
  end

  defp tarjan_strongconnect(workflow, node_key, state) do
    # Set depth index for node_key
    state = %{
      state
      | indices: Map.put(state.indices, node_key, state.index),
        lowlinks: Map.put(state.lowlinks, node_key, state.index),
        index: state.index + 1,
        stack: [node_key | state.stack],
        on_stack: MapSet.put(state.on_stack, node_key)
    }

    # Consider successors of node_key
    successors = get_successor_nodes(workflow, node_key)

    state =
      Enum.reduce(successors, state, fn successor, acc ->
        cond do
          not Map.has_key?(acc.indices, successor) ->
            # Successor has not yet been visited; recurse on it
            acc = tarjan_strongconnect(workflow, successor, acc)
            lowlink = min(Map.get(acc.lowlinks, node_key), Map.get(acc.lowlinks, successor))
            %{acc | lowlinks: Map.put(acc.lowlinks, node_key, lowlink)}

          MapSet.member?(acc.on_stack, successor) ->
            # Successor is in stack and hence in the current SCC
            lowlink = min(Map.get(acc.lowlinks, node_key), Map.get(acc.indices, successor))
            %{acc | lowlinks: Map.put(acc.lowlinks, node_key, lowlink)}

          true ->
            acc
        end
      end)

    # If node_key is a root node, pop the stack and create an SCC
    if Map.get(state.lowlinks, node_key) == Map.get(state.indices, node_key) do
      {scc_nodes, remaining_stack} = pop_scc_from_stack(state.stack, node_key, [])
      scc = MapSet.new(scc_nodes)
      on_stack = Enum.reduce(scc_nodes, state.on_stack, &MapSet.delete(&2, &1))

      %{state | stack: remaining_stack, on_stack: on_stack, sccs: [scc | state.sccs]}
    else
      state
    end
  end

  defp pop_scc_from_stack([head | tail], target, acc) do
    new_acc = [head | acc]

    if head == target do
      {new_acc, tail}
    else
      pop_scc_from_stack(tail, target, new_acc)
    end
  end

  # Get successor nodes for a given node
  defp get_successor_nodes(%Workflow{connections: connections}, node_key) do
    case Map.get(connections, node_key) do
      nil ->
        []

      ports ->
        ports
        |> Enum.flat_map(fn {_port, conns} -> Enum.map(conns, & &1.to) end)
        |> Enum.uniq()
    end
  end

  # ============================================================================
  # Loop Processing and Hierarchy
  # ============================================================================

  # Filter SCCs to only include actual loops (size > 1 or self-loops)
  defp filter_loops(sccs, workflow) do
    sccs
    |> Enum.with_index()
    |> Enum.filter(fn {scc, _index} ->
      MapSet.size(scc) > 1 or has_self_loop?(scc, workflow)
    end)
    |> Enum.map(fn {scc, index} ->
      %{
        id: "loop_#{index + 1}",
        nodes: scc,
        # Will be updated in hierarchy building
        level: 0
      }
    end)
  end

  # Check if a single-node SCC has a self-loop
  defp has_self_loop?(scc, workflow) do
    if MapSet.size(scc) == 1 do
      [node_key] = MapSet.to_list(scc)
      successors = get_successor_nodes(workflow, node_key)
      node_key in successors
    else
      false
    end
  end

  # Build hierarchy of nested loops
  defp build_loop_hierarchy(loops) do
    # For each loop, determine which other loops it contains
    Enum.map(loops, fn loop ->
      containing_loops =
        loops
        |> Enum.filter(fn other_loop ->
          other_loop.id != loop.id and MapSet.subset?(loop.nodes, other_loop.nodes)
        end)
        |> length()

      %{loop | level: containing_loops + 1}
    end)
  end

  # ============================================================================
  # Node Annotation
  # ============================================================================

  # Annotate nodes with loop information
  defp annotate_nodes_with_loop_info(nodes, loop_hierarchy) do
    # Build lookup map for which loops each node belongs to
    node_to_loops = build_node_to_loops_map(loop_hierarchy)

    Enum.map(nodes, fn node ->
      case Map.get(node_to_loops, node.key) do
        nil ->
          node

        node_loops ->
          max_level = Enum.max_by(node_loops, & &1.level).level
          loop_ids = Enum.map(node_loops, & &1.id)
          loop_role = determine_loop_role(node, node_loops)

          metadata =
            Map.merge(node.metadata, %{
              loop_level: max_level,
              loop_role: loop_role,
              loop_ids: loop_ids
            })

          %{node | metadata: metadata}
      end
    end)
  end

  defp build_node_to_loops_map(loop_hierarchy) do
    loop_hierarchy
    |> Enum.flat_map(fn loop ->
      loop.nodes
      |> MapSet.to_list()
      |> Enum.map(fn node_key -> {node_key, loop} end)
    end)
    |> Enum.group_by(fn {node_key, _loop} -> node_key end, fn {_node_key, loop} -> loop end)
  end

  # Determine the role of a node in loops (start_loop, in_loop, end_loop)
  # Uses simple heuristic: first node alphabetically is start_loop, last is end_loop
  defp determine_loop_role(node, node_loops) do
    # Get the most nested loop for role determination
    primary_loop = Enum.max_by(node_loops, & &1.level)
    sorted_nodes = primary_loop.nodes |> MapSet.to_list() |> Enum.sort()

    cond do
      node.key == List.first(sorted_nodes) -> :start_loop
      node.key == List.last(sorted_nodes) -> :end_loop
      true -> :in_loop
    end
  end
end
