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

- **@xyflow/react**: `^12.8.2` - Modern React Flow library for interactive node-based workflows
- **React**: `^19.1.1` - Latest React version with concurrent features
- **class-variance-authority**: `^0.7.1` - Utility for creating class name variants
- **clsx**: `^2.1.1` - Utility for conditionally constructing classNames
- **lucide-react**: `^0.533.0` - Beautiful & consistent icon toolkit
- **tailwind-merge**: `^3.3.1` - Merge Tailwind CSS classes without style conflicts

### UI Components Architecture

**Component Structure:**
- `assets/js/components/WorkflowLayout.jsx` - Main layout component with sidebar integration
- `assets/js/components/WorkflowSidebar.jsx` - Sidebar with integrations and actions
- `assets/js/components/ui/` - Reusable UI components (button, dialog, input, etc.)
- `assets/js/react_flow_hook.js` - Phoenix hook for React Flow integration

**Key Features:**
- **Monaco Editor Integration**: JSON editing with syntax highlighting for node parameters
- **Custom Node Types**: Visual node components with icons, actions, and inline editing
- **Sidebar Layout**: Collapsible sidebar with search and integration filtering
- **Modal Dialogs**: Node editing with tabbed interface (Params/Settings)
- **Real-time Sync**: Bidirectional state synchronization between React and LiveView
- **File Export**: JSON workflow export functionality

### Architecture Details

**LiveView Integration:**
- Phoenix hook manages React component lifecycle
- Data attributes pass initial state (`data-workflow`, `data-integrations`, etc.)
- Event handlers for workflow changes, node selection, and title updates
- File download handled via Phoenix events and blob creation

**State Management:**
- LiveView maintains authoritative workflow state
- React Flow hooks manage local UI state (nodes/edges)
- Debounced updates prevent excessive re-renders
- Node editing uses controlled components with validation

**Monaco Editor Setup:**
- Loaded dynamically via CDN (`monaco-editor@0.44.0`)
- JSON language support with formatting and validation
- Keyboard shortcuts (Ctrl+Shift+F for formatting)
- Proper cleanup on component unmount

The application demonstrates advanced Phoenix LiveView patterns for integrating complex JavaScript libraries while maintaining server-side state authority and real-time updates.