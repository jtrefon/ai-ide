# Language Support Configuration

This folder is the single source of truth for language behavior configuration.

## Structure

- `Languages/*.json`: full language support profiles (highlighting + styling + formatting + linting registry).
- `Themes/*.json`: optional shared theme palettes (fallback when language files do not override colors).

## Language support schema

```json
{
  "schemaVersion": 1,
  "language": "typescript",
  "highlighting": {
    "keywords": ["if", "return"],
    "typeKeywords": ["string", "number"],
    "booleanLiterals": ["true", "false"],
    "nullLiterals": ["null", "undefined"]
  },
  "styling": {
    "tokenColors": {
      "keyword": "#569CD6",
      "type": "#4EC9B0",
      "number": "#D19A66",
      "string": "#CE9178",
      "comment": "#6A9955"
    },
    "fontTraitsByRole": {
      "keyword": "semibold",
      "comment": "italic"
    },
    "preferredFontFamily": null
  },
  "formatting": {
    "indentUnitStyle": "spaces",
    "indentWidth": 2,
    "trimTrailingWhitespace": true,
    "ensureTrailingNewline": true,
    "maxConsecutiveBlankLines": 1
  },
  "linting": {
    "registry": "builtin.typescript",
    "rules": [
      {
        "id": "no-explicit-any",
        "severity": "warning",
        "enabled": true,
        "message": "Avoid explicit any where possible",
        "options": {}
      }
    ]
  }
}
```

## Compatibility

- Legacy language files containing only `keywords`, `typeKeywords`, `booleanLiterals`, `nullLiterals` are still supported.
- Missing `styling`, `formatting`, or `linting` blocks fall back to built-in defaults.

## Theme schema

```json
{
  "schemaVersion": 1,
  "themeName": "default",
  "languages": {
    "javascript": {
      "keyword": "#4A90E2",
      "type": "#B779FF",
      "boolean": "#FF9F0A",
      "null": "#FF9F0A",
      "number": "#FF9F0A",
      "string": "#FF5E57",
      "comment": "#58D68D"
    }
  }
}
```

## Runtime resolution order

For language support files:

1. `OSX_IDE_HIGHLIGHT_DEFINITIONS_DIR` (if set)
2. App bundle path: `Highlighting/Languages/*.json`
3. Built-in Swift fallback defaults

For theme files:

1. `OSX_IDE_HIGHLIGHT_THEMES_DIR` (if set)
2. App bundle path: `Highlighting/Themes/default.json`
3. Built-in Swift fallback colors
