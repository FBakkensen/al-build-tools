---
applyTo: '**'
---
**AL Research-First Approach**: Your AL knowledge may be outdated. You MUST use available research tools to gather current AL and Business Central information:

**YOU MUST COMPLETE ALL OF THE FOLLOWING AL RESEARCH STEPS:**

1. **MANDATORY: Project Documentation Analysis** - If a `.aidocs` folder exists in the workspace, you MUST analyze it to understand the current AL project context. Start with `index.md` as the main entry point, then review relevant documentation files to understand the project's AL architecture, Business Central data model, business flows, and AL technical patterns.

2. **MANDATORY: AL Guidelines via Context7** – Use `#context7` tools (`mcp_context7_resolve-library-id` and `mcp_context7_get-library-docs`) with library `microsoft/alguidelines` to research current AL/Business Central coding guidelines including: AL object naming conventions (PascalCase, meaningful names, AL prefixes), AL code style (4-space indentation), AL performance optimization (SetLoadFields, proper AL filtering), AL extension-model patterns, and AL event-driven architecture.

3. **MANDATORY: Microsoft Documentation** - Use `#microsoft.docs.mcp` to search for relevant Microsoft AL/Business Central documentation including best practices for: AL file naming conventions, AL object structure, AL variable naming, AL method declarations, and Business Central integration standards.

4. **HIGHLY RECOMMENDED: Business Central Code For Standard Microsoft Apps** - Use `#mcp_github_search_code` to search repository `FBakkensen/bc-w1` for AL code patterns including: AL workflow implementations, AL event handling, Business Central role center patterns, AL approval workflows, and standard AL object structures (do NOT implement these patterns - only reference them for AL guidance).

5. **HIGHLY RECOMMENDED: Business Central Innovation Examples** - Use `#mcp_github_search_code` to search repository `microsoft/bctech` for cutting-edge AL code patterns including: experimental AL workflows, advanced AL event handling, innovative Business Central role center designs, prototype AL approval systems, and emerging AL object structures from Microsoft's R&D team (do NOT implement these patterns - only reference them for AL guidance).

6. **CONTEXTUAL: URL Content Analysis** - If the user provides URLs, use `fetch_webpage` to retrieve AL/Business Central content and recursively fetch any additional relevant AL links found until you have all necessary AL information.

**Note: Failure to complete the mandatory AL research steps will result in an incomplete AL implementation.**
