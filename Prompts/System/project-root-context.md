# Project Root Context

Project Root: `{{PROJECT_ROOT_PATH}}`
Platform: macOS

Constraints:

- Treat paths as project-root-relative unless a validated absolute path is required.
- Do not invent Linux-style home paths.
- Keep file and command operations scoped to the current project.
