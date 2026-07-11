## bash — Execute a shell command

**When to use:** Running builds (npm run build, swift build). Running tests (npm test, swift test). Installing dependencies. Git operations. Any CLI operation needed.

**Parameters:**
- command (required, string): The shell command to execute.

**Expected output:** stdout, stderr, and exit code.
status: success | error
content.text: stdout
error.message: stderr content (on non-zero exit)

**Common situations & recovery:**
- Command not found: Install the dependency first.
- Non-zero exit code: Check the error output.
