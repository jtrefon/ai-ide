# Prompt Fallback Feature Flag

## Overview

The `PromptRepository` includes an explicit fallback control to determine whether hardcoded defaults are allowed when external prompt files are missing or empty.
The strict `prompt(key:projectRoot:)` API is for production call sites.
The explicit `fallbackPrompt(key:defaultValue:allowFallback:projectRoot:)` API is for development and test-only fallback behavior.

## Fallback Control

```swift
try PromptRepository.shared.fallbackPrompt(
    key: "ConversationFlow/Corrections/example",
    defaultValue: "Fallback prompt text",
    allowFallback: true,
    projectRoot: projectRoot
)
```

- **Default production path**: use `prompt(key:projectRoot:)`
- **Fallback control**: pass `allowFallback: true` only at explicit fallback call sites

## Behavior

### When `allowFallback = false`
- Only external prompt files are used
- If a file is missing → `AppError.promptLoadingFailed`
- If a file is empty → `AppError.promptLoadingFailed`
- If a file can't be read → `AppError.promptLoadingFailed`
- **Purpose**: Fail fast to ensure all required prompt files exist

### When `allowFallback = true`
- `prompt(key:projectRoot:)` remains strict and still throws when prompt files are missing or invalid
- `fallbackPrompt(key:defaultValue:allowFallback:projectRoot:)` uses external files when available
- If a file is missing/empty/unreadable and `fallbackPrompt(...)` is used → returns the provided `defaultValue`
- **Purpose**: Graceful degradation for development/testing

## Usage

### Allow Fallback (for development/testing)
```swift
try PromptRepository.shared.fallbackPrompt(
    key: "ConversationFlow/Corrections/example",
    defaultValue: "Fallback prompt text",
    allowFallback: true,
    projectRoot: projectRoot
)
```

### Keep Production Strict
```swift
try PromptRepository.shared.prompt(
    key: "ConversationFlow/Corrections/example",
    projectRoot: projectRoot
)
```

## Implementation Details

The explicit `allowFallback` parameter is checked in `PromptRepository.fallbackPrompt()` at three points:

1. **File Resolution**: When `resolvePromptURL()` returns `nil`
2. **File Reading**: When `Data(contentsOf:)` or `String(data:encoding:)` fails
3. **Empty Content**: When trimmed file content is empty

Each failure point provides a specific error explaining:
- What failed (missing file, unreadable file, empty file)
- The key that was requested
- The expected file path
- Instructions to fix the issue

## Testing

The feature flag is covered by `PromptRepositoryTests` with 6 test cases:

1. `testPromptRepositoryFallbackDisabled()` - Verifies existing files work with fallback disabled
2. `testPromptRepositoryFallbackEnabled()` - Verifies missing files return defaults with fallback enabled  
3. `testPromptRepositoryExistingFileWithFallbackEnabled()` - Verifies existing files still work with fallback enabled
4. `testPromptRepositoryPromptRemainsStrictWhenExplicitFallbackIsAllowed()` - Verifies the strict API still throws for missing prompts
5. `testPromptRepositoryEmptyFileWithFallbackEnabled()` - Verifies empty files return defaults with fallback enabled
6. `testPromptRepositoryMissingPromptThrowsWhenFallbackDisabled()` - Verifies explicit fallback calls still throw when fallback is disabled

## Benefits

1. **Full Control**: You know exactly which prompts are being used
2. **No Randomness**: Eliminates runtime decision making about prompt sources
3. **Fail Fast**: Missing prompt files are immediately detected in development
4. **Optimization Ready**: Enables systematic prompt optimization without hidden fallbacks
5. **Chaos Prevention**: Eliminates unexpected behavior from hardcoded defaults

## Migration

To migrate your codebase to use this fallback control:

1. **Ensure all prompt files exist**: Check the prompt analysis to identify missing files
2. **Add missing prompt files**: Create the missing prompt files identified in the analysis
3. **Use the strict API in production**: Prefer `prompt(key:projectRoot:)` for normal runtime call sites
4. **Use the explicit fallback API only where intended**: Restrict `fallbackPrompt(...)` to development or test-only flows
5. **Test both strict and fallback paths**: Cover both `allowFallback: false` and `allowFallback: true`
6. **Keep production strict by default**: Only pass `allowFallback: true` at call sites that intentionally opt into fallback behavior

This feature flag gives you complete control over prompt usage while maintaining the flexibility needed for development workflows.
