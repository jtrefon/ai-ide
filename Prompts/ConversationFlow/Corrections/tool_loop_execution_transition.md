You have gathered context primarily with read-only tools, and now execution is required.

Transition to concrete implementation now:
1. Use write_files for multi-file scaffolding/coordinated creation.
2. Use write_file for single-file create/overwrite.
3. Use replace_in_file to modify existing files.
4. Use run_command for finite build/test commands.

User request:
{{user_input}}

Context gathered:
{{tool_summary}}
