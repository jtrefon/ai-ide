# Windows and MacOS native IDE with Agentic AI

This is vscode inspired layout IDE with project/directory browser to the left, main code area in the center, Agentic AI to the right and terminal (powershell in Windows) at the botom of the center. We will use two straps bottom and left for icons and status display (just like vscode) and tabs for file editing. Bottom left cogg icon will open settings. Left panel will have file explorer, search, source control, and extensions views.

## Features

- Project/Directory browser
- Main code editing area
- Agentic AI integration
- Terminal (PowerShell) at the bottom
- Status display and icons
- File editing tabs
- Settings access
- File explorer, search, source control, and extensions views
- Syntax highlighting and code completion
- Model selection
- Code execution
- Mode selection: (e.g., Ask, Agent)

## AI Agent

We will support openrouter models and provide a seamless integration with the Agentic AI for enhanced coding assistance and automation. Agentic AI will be able to understand and respond to natural language queries, provide code suggestions, and automate repetitive tasks, making the development process more efficient and enjoyable. We will use tool calls to interact with the AI and leverage its capabilities. We build tools for agent to execute, those tools are:

- search codebase
- browse codebase
- read file contents (multiple files at once)
- write file contents (multiple files at once)
- patch file contents (multiple files at once)
- delete file contents (multiple files at once)
- create, delete files (multiple files at once)
- execute terminal commands, read output

## Stack

IDE will be built in .net9 using MAUI for cross-platform support. Will use async/await for asynchronous programming. Will leverage dependency injection for better testability and modularity for extensibility. Will use multi-threading for improved performance and responsiveness.

## Architecture

The architecture of the IDE will follow a modular design, allowing for easy integration of new features and tools. The main components will include:

- **Frontend**: Built using .NET MAUI, providing a responsive and intuitive user interface across platforms.
- **Backend**: DLL based architecture for handling AI interactions/tooling, file operations, and project management.
- **AI Integration**: Seamless communication with the Agentic AI for enhanced coding assistance and automation using openrouter api.
- **Plugin System**: Support for extensions and plugins to allow users to customize their development environment. SDK / plugin specification will be built and expose APIs for easy integration.
- **State Management**: Efficient handling of application state to ensure a smooth user experience. Full application indexing will be implemented to support fast search and navigation.

## Rollback Mechanism

In order to ensure a smooth development experience, the IDE will implement a rollback mechanism that allows users to revert changes made to their codebase. This feature will be particularly useful in the following scenarios:

- Accidental changes: If a user accidentally modifies or deletes code, they can easily revert to a previous version.
- Experimentation: Users can experiment with new features or changes without the fear of permanently affecting their codebase.
- Collaboration: In a team environment, the rollback mechanism can help resolve conflicts and maintain code integrity.

The rollback mechanism will be integrated with the version control system, allowing users to access previous commits and changes easily.

Each change made in the codebase will be tracked, and users will have the ability to revert to any previous state with ease.

Each task will create new feature branches in the version control system, allowing for isolated development and easy merging of changes.


## Coding Standards and Best Practices

- Follow SOLID principles for software design.
- Write clean, maintainable, and modular code.
- Follow clean code practices, multi tier architecture and continuous improvement/refactoring.
- Use design patterns where applicable.
- Follow DRY, KISS and YAGNI principles.
- Prioritize readability and simplicity in code.
- Keep functions small and focused on a single task, strictly follow single responsibility principle.
- Class length should never exceed 200 lines.
- Avoid deep nesting of code blocks.
- Keep methods short and focused on a single task, dont exceed 20 lines.
- Use helper functions to reduce code duplication, keep strong and well documented public API.
- Use strong and clean abstractions to eliminate rigid dependencies.
- Use consistent naming conventions and code formatting.
- Write unit tests for all new features and bug fixes.
- Document code and APIs thoroughly.
- Conduct code reviews to maintain code quality.