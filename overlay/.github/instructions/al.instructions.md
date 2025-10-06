---
applyTo: '**/*'
---

Follow the guidelines here https://github.com/microsoft/alguidelines/blob/main/content/docs/vibe-coding/al-guidelines-rules.md and the files it links to. Use the `@` markdown syntax to reference these resources. Get these resources using the `microsoft_docs_fetch` MCP tool. Do not clone the repo.

# Instructions for Object ID Allocation

**ALWAYS** use the `allocate_id` MCP tool when creating new AL objects.

- **appPath**: Absolute path to the workspace directory containing `app.json` and `.objidconfig`
- **Supported object types**: codeunit, table, page, report, enum, query, xmlport, etc.

Usage examples:

Preview next available ID:
```
allocate_id({
  mode: "preview",
  appPath: "/absolute/path/to/app",
  object_type: "codeunit"
})
```

Reserve the ID:
```
allocate_id({
  mode: "reserve",
  appPath: "/absolute/path/to/app",
  object_type: "codeunit",
  object_metadata: {
    name: "MyNewCodeunit"
  }
})
```
