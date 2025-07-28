# Built-in Integrations

Prana includes several core integrations that provide essential workflow functionality. These integrations are built into the system and available by default.

> **Note**: This document has been reorganized. For detailed information about each integration, see the individual integration documents in the [`integrations/`](integrations/) directory.

## Core Integrations

### [Manual Integration](integrations/manual.md)
**Purpose**: Testing and development utilities  
**Category**: Test  
**Module**: `Prana.Integrations.Manual`

Simple test actions for workflow development and testing scenarios.

### [Logic Integration](integrations/logic.md)
**Purpose**: Conditional branching and control flow operations  
**Category**: Core  
**Module**: `Prana.Integrations.Logic`

Conditional routing capabilities for workflow execution, enabling IF/ELSE branching and multi-case switch routing.

### [Data Integration](integrations/data.md)
**Purpose**: Data manipulation and combination operations  
**Category**: Core  
**Module**: `Prana.Integrations.Data`

Essential data manipulation capabilities for combining and processing data from multiple workflow paths.

### [Workflow Integration](integrations/workflow.md)
**Purpose**: Sub-workflow orchestration and coordination  
**Category**: Coordination  
**Module**: `Prana.Integrations.Workflow`

Sub-workflow execution capabilities with suspension/resume patterns for parent-child workflow coordination.

### [Wait Integration](integrations/wait.md)
**Purpose**: Time-based workflow control with delays, scheduling, and webhooks  
**Category**: Control  
**Module**: `Prana.Integrations.Wait`

Comprehensive time-based workflow control capabilities, supporting interval delays, scheduled execution, and webhook-based external event waiting.

### [HTTP Integration](integrations/http.md)
**Purpose**: HTTP request actions and webhook triggers  
**Category**: Network  
**Module**: `Prana.Integrations.HTTP`

HTTP request capabilities and webhook trigger functionality for external API interactions and incoming HTTP request handling.

### [Code Integration](integrations/code.md)
**Purpose**: Secure execution of user-provided Elixir code  
**Category**: Development  
**Module**: `Prana.Integrations.Code`

Secure sandbox environment for executing user-provided Elixir code with comprehensive security validation and dual-mode execution (interpreted/compiled).

## Creating Custom Integrations

For information on creating custom integrations, see the [Writing Integrations Guide](guides/writing_integrations.md).