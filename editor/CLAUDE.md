# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

**Setup and Dependencies:**
- `mix setup` - Install and setup all dependencies (runs deps.get, assets.setup, assets.build)
- `mix deps.get` - Install Elixir dependencies only

**Running the Application:**
- `mix phx.server` - Start Phoenix server (visit localhost:4000)
- `iex -S mix phx.server` - Start server in interactive Elixir shell

**Asset Management:**
- `mix assets.setup` - Install frontend build tools (Tailwind, ESBuild)
- `mix assets.build` - Build assets for development
- `mix assets.deploy` - Build and minify assets for production

**Testing:**
- `mix test` - Run the test suite
- `mix test test/path/to/specific_test.exs` - Run a specific test file

## Architecture Overview

This is a **Phoenix LiveView application** that implements a visual workflow editor using React Flow integrated via Phoenix hooks.

### Key Components

**Backend (Elixir/Phoenix):**
- `lib/editor_web/live/workflow_live.ex` - Main LiveView module handling workflow state and events
- Uses Phoenix LiveView for real-time UI updates and state management
- JSON export functionality via `export_json` event handler
- Workflow state stored as nodes and edges data structures

**Frontend Integration:**
- `assets/js/react_flow_hook.js` - Phoenix hook that integrates React Flow library
- React Flow runs inside Phoenix LiveView via JavaScript interop
- Real-time bidirectional communication between React Flow and LiveView
- File download functionality for workflow export

**Asset Pipeline:**
- Uses ESBuild for JavaScript bundling
- Tailwind CSS for styling with JIT compilation
- Assets are compiled from `assets/` directory
- React and React Flow are imported dynamically via ES modules

### Data Flow

1. LiveView maintains workflow state (nodes/edges) in Elixir
2. React Flow hook receives initial data via `data-workflow` attribute
3. User interactions in React Flow trigger events sent back to LiveView
4. LiveView updates state and re-renders with new data
5. React Flow hook updates the visual interface accordingly

### Frontend Dependencies

- **Main assets/**: React Flow (`reactflow: ^11.11.4`)
- **Editor assets/**: React 19 (`react: ^19.1.1`, `react-dom: ^19.1.1`)

The application demonstrates Phoenix LiveView's capability to integrate with complex JavaScript libraries while maintaining server-side state management.