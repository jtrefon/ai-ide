# Prompt Fallback Feature Flag

## Overview

The `PromptRepository` now includes a feature flag to control whether fallback to hardcoded defaults is allowed when external prompt files are missing or empty.

## Feature Flag

```swift
@MainActor
static var allowFallback: Bool = false
```

- **Default**: `false` (fallback disabled)
- **Location**: `PromptRepository.allowFallback`

## Behavior

### When `allowFallback = false` (Default)
- Only external prompt files are used
- If a file is missing → `fatalError` with descriptive message
- If a file is empty → `fatalError` with descriptive message  
- If a file can't be read → `fatalError` with descriptive message
- **Purpose**: Fail fast to ensure all required prompt files exist

### When `allowFallback = true`
- External files are used when available
- If a file is missing/empty/unreadable → returns the provided `defaultValue`
- **Purpose**: Graceful degradation for development/testing

## Usage

### Enable Fallback (for development/testing)
```swift
@MainActor
func setupDevelopmentMode() {
    PromptRepository.allowFallback = true
}
```

### Disable Fallback (production)
```swift
@MainActor
func setupProductionMode() {
    PromptRepository.allowFallback = false
}
```

## Implementation Details

The feature flag is checked at three points in `PromptRepository.prompt()`:

1. **File Resolution**: When `resolvePromptURL()` returns `nil`
2. **File Reading**: When `Data(contentsOf:)` or `String(data:encoding:)` fails
3. **Empty Content**: When trimmed file content is empty

Each failure point provides a specific `fatalError` message explaining:
- What failed (missing file, unreadable file, empty file)
- The key that was requested
- The expected file path
- Instructions to fix the issue

## Testing

The feature flag is covered by `PromptRepositoryTests` with 5 test cases:

1. `testPromptRepositoryFallbackDisabled()` - Verifies existing files work with fallback disabled
2. `testPromptRepositoryFallbackEnabled()` - Verifies missing files return defaults with fallback enabled  
3. `testPromptRepositoryExistingFileWithFallbackEnabled()` - Verifies existing files still work with fallback enabled
4. `testPromptRepositoryFeatureFlagToggle()` - Verifies the flag can be toggled
5. `testPromptRepositoryEmptyFileWithFallbackEnabled()` - Verifies empty files return defaults with fallback enabled

## Benefits

1. **Full Control**: You know exactly which prompts are being used
2. **No Randomness**: Eliminates runtime decision making about prompt sources
3. **Fail Fast**: Missing prompt files are immediately detected in development
4. **Optimization Ready**: Enables systematic prompt optimization without hidden fallbacks
5. **Chaos Prevention**: Eliminates unexpected behavior from hardcoded defaults

## Migration

To migrate your codebase to use this feature flag:

1. **Ensure all prompt files exist**: Check the prompt analysis to identify missing files
2. **Add missing prompt files**: Create the missing prompt files identified in the analysis
3. **Test with fallback disabled**: Run your tests with `allowFallback = false`
4. **Keep fallback enabled for development**: Use `allowFallback = true` during active development
5. **Set fallback disabled for production**: Ensure `allowFallback = false` in production builds

This feature flag gives you complete control over prompt usage while maintaining the flexibility needed for development workflows.
