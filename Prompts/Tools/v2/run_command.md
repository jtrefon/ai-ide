# run_command Tool

## Purpose
Execute a shell command in the project directory and return its stdout, stderr, and exit code.

## Environment
- **OS**: macOS (Darwin)
- **Shell**: zsh
- **Available tools**: swift, python3, node, npm, git, curl, grep, sed, awk, and all standard macOS CLI tools
- **Project root**: The working directory for all commands

## When to Use
- Running builds: npm run build, swift build, python setup.py
- Running tests: npm test, swift test, pytest
- Installing dependencies: npm install, pip install
- Running linters or formatters
- Git operations: git status, git diff, git log
- Any CLI operation needed for the project

## When NOT to Use
- Do NOT use for file operations — use read_file, write_file, patch_file instead
- Do NOT use for interactive/long-running processes without setting isInteractive
- Do NOT use for destructive operations (rm -rf) without user confirmation

## Parameters
- **command** (required, string): The shell command to execute.
- **description** (required, string): Brief description of what this command does (for logging).
- **isInteractive** (optional, boolean): Set true for long-running processes (dev servers, watchers). Default false.

## Usage Examples
- Install deps: `{ "command": "npm install", "description": "Install dependencies" }`
- Run tests: `{ "command": "npm test", "description": "Run test suite" }`
- Build: `{ "command": "swift build", "description": "Build the project" }`

## Output Structure
Returns a ToolFeedback envelope:
- **status**: "success" | "error" | "partial"
- **content.text**: stdout content
- **error**: stderr content (if any)
- **message**: Exit code information

## Success Indicators
- Exit code 0 (zero) in the message
- stdout contains expected output

## Error Handling
- Non-zero exit code: Check stderr for error details
- Timeout: Command exceeded time limit. Consider breaking into smaller commands.
- Common issues: missing dependencies, wrong working directory, permission errors

## Best Practices
1. Always provide a clear description
2. Chain simple commands with && for efficiency
3. For install commands, prefer npm install over npm ci unless reproducing CI
4. Read build output carefully — errors may be mixed with warnings

## Integration Notes
- Commands run from the project root directory
- Environment inherits user's PATH and shell configuration
- Long-running processes (dev servers) should set isInteractive = true
