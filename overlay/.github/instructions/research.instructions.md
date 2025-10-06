---
applyTo: '**'
---
**AL Research Guidance (Right-Sized)**: Use the available research tools to stay current with AL & Business Central; scale effort to task complexity and risk.

> Scope Clarification: For trivial or purely mechanical changes (e.g., fixing a caption/tooltip, correcting spelling, adding a field with no business logic, adjusting permissions), you may execute only a lightweight subset (usually a quick symbol lookup from step 3) provided there is no data integrity, performance, architectural, or posting impact. Execute the full detailed workflow (all five steps) for any moderate or higher risk change: posting sequences, data model alterations, upgrade/migration logic, performance‑sensitive loops, concurrency considerations, or when ambiguity exists. Escalate progressively—start minimal, then deepen research only if uncertainty or risk is discovered.

1. **Core: Project Documentation Analysis** - If a `.aidocs` folder exists in the workspace, you MUST analyze it to understand the current AL project context. Start with `index.md` as the main entry point, then review relevant documentation files to understand the project's AL architecture, Business Central data model, business flows, and AL technical patterns.

2. **Core: Microsoft Documentation (Search & Fetch)** – Ground every design decision in authoritative docs:
	- SCOPE NOTE: Microsoft Docs surface ALL Business Central documentation (functional + setup + user + development). Your queries may return finance, inventory, warehouse, manufacturing, sales, analytics, or AL dev pages. This is expected; filter for what is normative for your task.
	- Search first with focused topic keywords (e.g., "AL file naming", "event subscriber best practices", "AL performance SetLoadFields").
	- Prioritize pages titled “Best practices for AL”, “Performance…”, “Subscribing to events”, “Working with translation files”, “Table keys”.
	- Fetch full documentation ONLY for: full procedural steps, property tables, performance pattern details, or when search excerpt insufficient.
	- Do not fetch multiple pages blindly: fetch the top-most relevant single page, extract needed rules, then decide if more pages are required.
	- Capture only normative rules (naming, ordering, required properties, performance constraints). Avoid copying long narrative text.
	- If conflicting guidance appears, prefer: (1) current release docs (non-archived) > (2) best practices page > (3) older release notes.
	- Treat absence of a rule in docs as a signal to design minimally and rely on published events rather than internal replication.

3. **Core: Dependency Symbol Intelligence** – Use available AL symbol tools to inspect objects from dependent packages (Base Application, System, other dependencies) before implementing changes. This is for understanding compiled dependencies, NOT for exploring source code in this codebase (use file system tools for that):
	- Load symbol packages from dependency .app files
	- Search for objects by name, type, or pattern to locate relevant tables, pages, codeunits
	- Get object summaries to understand structure without full details
	- Search for specific procedures, fields, or events within objects
	- Find references to understand how objects are extended or used
	- Only retrieve full object definitions when necessary
	- Prefer summaries and targeted searches first for performance

4. **Core: Combined Symbol → Source Workflow** – Always derive targets locally, then query external repositories only if needed:
	- Local First: Use symbols to list objects, procedures, events. Stop if an existing event solves it.
	- Escalate Only If: Logic sequence unclear (hidden body) OR need surrounding event context OR evaluating alternative pattern OR validating need for new event.
	- Targeted Repository Searches (never clone repositories):
		- Search for specific code patterns (e.g., "PostItemJnlLineTracking" in repository FBakkensen/bc-w1, limit to 5 results)
		- Search within specific paths (e.g., "codeunit 80" in Sales path of FBakkensen/bc-w1)
		- Search for exact event signatures (e.g., "OnPostItemJnlLineTrackingOnAfterCalcShouldInsertTrkgSpecInv" in FBakkensen/bc-w1)
	- Extract Pattern Only: Capture order, conditions, data transformations; re-implement via events/subscribers. Do NOT copy blocks.
	- Version Conflicts: If external source differs, trust local symbols; treat external result as historical.
	- Minimal Retrieval: Search specific identifiers, not whole posting modules.
	- Red Flag: If you need large contiguous internal code, reconsider approach (find event, request new event, or redesign).

5. **Core: External Repository Research (microsoft/alguidelines, microsoft/bctech, FBakkensen/bc-w1)** – Use available repository research tools (never clone repositories). Focus on extracting current, authoritative and practical patterns:
	- `microsoft/alguidelines` (Authoritative Standards): Sourcing formal AL coding conventions: naming (PascalCase, prefixes), indentation (4 spaces), performance guidance references (SetLoadFields, filtering), event-driven principles. Prioritize guideline markdown / docs over sample code when conflicts arise.
	- `microsoft/bctech` (Innovative & Scenario Samples): Educational & exploratory samples (AI/Copilot integration, telemetry & performance CTF challenges, migration, extensibility). Treat performance challenge code as intentional anti-pattern demonstrations unless an optimized solution section is shown.
	- `FBakkensen/bc-w1` (Base Application Reference): Mirrors core W1 application patterns: event publishers/subscribers, posting routines, role centers, workflow triggers, permission/set usage, data seeding strategies.