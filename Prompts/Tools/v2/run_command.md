# Tool: run_command

WHAT: Executes a shell command in the project directory and returns its stdout, stderr, and exit code.

WHEN: Use for running builds (npm run build, swift build), executing tests (npm test, swift test), installing dependencies (npm install), running linters, or any CLI operation needed for the project.

HOW:
- command (required, string): The shell command to execute.
- description (required, string): A brief description of what this command does (used for logging and tracking).
- isInteractive (optional, bool): Set to true for long-running processes like dev servers. Default false.
- Overloading: For simple commands, just pass command and description. For install commands, chain with &&. For background processes, set isInteractive.

OUTPUT: Returns stdout content, stderr content, and the exit code. A zero exit code indicates success.
