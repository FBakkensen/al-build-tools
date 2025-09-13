---
mode: 'agent'
---
## Revised GitHub Copilot Prompt for In-Depth AL Project Analysis (Business Central)

**Objective:** Perform an exhaustive analysis of the entire AL codebase of the currently open Business Central project in VS Code. Your primary goal is to generate a highly detailed and structured set of Markdown documents. This documentation must serve as a comprehensive onboarding guide for a developer entirely new to this specific codebase, enabling them to understand its architecture, components, data structures, key functionalities, adherence to best practices, and potential areas for improvement. All output documentation must be placed within a folder named `aidocs` at the root of the project, following the precise file structure and content requirements outlined below.

**Core Instructions for Copilot - Perform In-Depth Codebase Research and Analysis:**

Your analysis should go beyond surface-level observations. Actively "research" the codebase by tracing logic, identifying patterns, and inferring relationships. Refer to established AL development best practices (such as those from Microsoft and `alguidelines.dev`) when evaluating the code.

**I. Project Overview and Initial Setup (`aidocs/01_project_overview.md`):**

1.  **Project Identification & Purpose:**
    *   Scan `app.json`: Extract and list project `id`, `name`, `publisher`, `version`, `brief`, `description`, `privacyStatement`, `EULA`, `help`, `url`, `logo`, `dependencies`, `screenshots`, `platform`, `application`, `idRanges`, `runtime`, `features`.
    *   Infer and describe the primary business domain and overall purpose of the extension based on its name, description, and the nature of its objects. Be specific.
    *   Identify the target Business Central version compatibility (from `platform` and `application` versions).
2.  **Development Environment & Practices (Inferred):**
    *   Check for a `.vscode/settings.json` file. If present, list any AL-specific settings related to `al.ruleSetPath`, `al.codeAnalyzers`, `al.enableCodeAnalysis`, or custom formatter settings. Describe their implications.
    *   Check for a custom ruleset file (e.g., `*.ruleset.json`). If found, list the analyzers it targets (CodeCop, AppSourceCop, etc.) and any modified rules (e.g., changes in severity from default). Explain the significance of these customizations.
    *   Identify if `LinterCop` or other third-party analyzers seem to be configured (look for custom DLL paths in settings or specific rule prefixes in diagnostic messages if you can access them).

**II. Codebase Structure and Conventions (`aidocs/02_codebase_structure.md`):**

1.  **Folder and File Structure:**
    *   Describe the overall folder structure within the `src` directory (or equivalent source folder). Are objects grouped into subfolders? If so, list the main functional groupings suggested by this structure.
    *   Analyze file naming conventions. Does the project adhere to `<ObjectName>.<FullTypeName>.al` or `<Prefix/Suffix><ObjectName>.<FullTypeName>.al`? Provide examples and note any inconsistencies.
    *   Specifically check for adherence to Microsoft's recommended abbreviations for object types in file names (e.g., `PageExt`, `TableExt`, `Codeunit`).
2.  **Object Naming Conventions:**
    *   Analyze object names (tables, pages, codeunits, etc.). Is there a consistent prefix or suffix used as per AppSource or partner best practices? Document this affix and provide examples.
    *   Assess if object names are descriptive and follow PascalCase.
3.  **Variable and Method Naming Conventions:**
    *   Analyze variable naming. Are they PascalCase? Is the `Temp` prefix used for temporary record variables? Are record variable names indicative of the record they hold (e.g., `CustomerRec` for `Record Customer`)?
    *   Analyze method (procedure/trigger) naming. Are they PascalCase? Are they descriptive?
4.  **Code Formatting and Readability:**
    *   Assess adherence to AL formatting best practices: lowercase for reserved keywords, four spaces for indentation, curly brackets on new lines. Note common deviations.
    *   Comment on the general readability of the code. Is it well-commented? Are lines excessively long?
5.  **Internal Object Structure:**
    *   For a representative sample of different object types (e.g., a complex page, a large table, a core codeunit), describe if they follow the standard internal structure: Properties -> Object-specific constructs (fields, layout, actions) -> Global Variables (labels, then other globals) -> Methods. Highlight any significant deviations.

**III. Architectural Analysis (`aidocs/03_architecture.md`):**

1.  **High-Level Architecture:**
    *   Describe the overall architectural style. Is it a monolithic extension, or does it exhibit characteristics of a modular design (e.g., distinct functional areas with clear interfaces)?
    *   Identify and list the main logical modules or components. A module/component is a group of AL objects (tables, pages, codeunits, reports, etc.) that collectively deliver a significant piece of functionality (e.g., "Advanced Sales Pricing", "Custom Inventory Reporting"). For each module:
        *   Provide a concise description of its purpose.
        *   List its key AL objects (top 5-10 most important ones per module).
2.  **Component Interaction and Dependencies:**
    *   Describe how these identified modules/components interact. Are interactions primarily through direct object calls, events, or interfaces?
    *   Generate a **Mermaid Component Diagram** (using `graph LR` or `graph TD`) illustrating these major modules and their primary dependencies. Example:
        ```mermaid
        graph TD;
            ModuleA[Sales Module] --> ModuleB[Inventory Module];
            ModuleA --> ModuleC[Finance Interface];
            ModuleD[Custom Reporting] --> ModuleA;
            ModuleD --> ModuleB;
        ```
3.  **Key Design Patterns (Inferred):**
    *   Identify any recurring design patterns used in the codebase. Examples:
        *   **Facade Pattern:** Are there codeunits acting as a simplified interface to a more complex subsystem?
        *   **Singleton Pattern:** Any codeunits designed to have only one instance (e.g., for managing global state or settings)?
        *   **Observer Pattern (Events):** Detail the use of event publishing and subscribing (see Section VI).
        *   **Strategy Pattern:** Are different algorithms or behaviors encapsulated and interchangeable?
        *   **Data Transfer Objects (DTOs):** Are temporary tables or specific record structures used primarily for passing data between layers or modules?
    *   For each identified pattern, provide specific examples from the code (object names, relevant procedures).
4.  **Potential Architectural Concerns / Anti-Patterns (Inferred):**
    *   Identify any potential architectural weaknesses or anti-patterns observed:
        *   **God Objects:** Are there any excessively large or complex objects (tables with too many fields, codeunits with too many responsibilities/lines of code)? Provide examples.
        *   **Tight Coupling:** Are modules or components overly dependent on each other's internal details?
        *   **Lack of Cohesion:** Do some modules/objects group unrelated functionalities?
        *   **Circular Dependencies** between modules/objects.
    *   Provide specific examples and explain the potential negative impact.

**IV. Data Model Analysis (`aidocs/04_data_model.md`):**

1.  **Core Entities and Relationships:**
    *   Identify ALL tables in the project. For each table, list its primary key and 5-10 most significant fields (excluding system fields like SystemId, SystemCreatedAt unless highly relevant to custom logic).
    *   Describe the primary relationships between these core tables (e.g., TableA has a one-to-many relationship with TableB via FieldX).
2.  **Entity-Relationship Diagram (ERD):**
    *   Generate a **Mermaid ER Diagram** for these core custom tables and their key relationships. Focus on clarity over including every single field. Example:
        ```mermaid
        erDiagram
            CUSTOMER ||--o{ ORDER : places
            ORDER ||--|{ LINE-ITEM : contains
            CUSTOMER }|..|{ ADDRESS : uses

            CUSTOMER {
                int id PK
                string name
                string email
            }
            ORDER {
                int id PK
                int customer_id FK
                date order_date
            }
            LINE-ITEM {
                int id PK
                int order_id FK
                string product_name
                int quantity
                decimal price
            }
            ADDRESS {
                int id PK
                int customer_id FK
                string street
                string city
            }
        ```
    *   If the project heavily extends standard tables, create a separate ERD or section detailing key standard tables and the custom fields/relations added to them via table extensions.
3.  **Key Enums and Option Fields:**
    *   Identify and list important custom Enums or Option fields that define critical states, types, or business rules. For each, list its possible values and their meanings.
4.  **Data Validation Logic:**
    *   Describe common patterns for data validation. Is it primarily in table triggers (`OnValidate`, `OnInsert`, `OnModify`), page triggers, or centralized in specific codeunits? Provide examples.

**V. Key Functionalities and Business Logic Flows (`aidocs/05_key_flows.md`):**

1.  **Identification of Core Processes:**
    *   Based on object names, comments, and code structure, identify ALL critical business processes or user workflows implemented or significantly modified by this extension.
    *   Examples: "Custom Sales Order Processing", "Automated Inventory Replenishment", "Special Discount Calculation".
2.  **Detailed Flow Analysis (for each identified process):**
    *   **Entry Points:** Identify the primary entry points for each flow (e.g., a specific page action, a job queue entry, an event subscriber).
    *   **Sequence of Operations:** Describe the step-by-step execution, listing the key AL objects (pages, codeunits, tables, reports) and specific procedures/triggers involved in sequence.
    *   **Data Transformations:** Explain how data is created, read, updated, or deleted during the flow.
    *   **Decision Points:** Highlight any significant conditional logic or decision points.
    *   **User Interaction:** Describe any user interactions involved (e.g., data entry on pages, confirmations).
3.  **Flow Diagrams (for each identified process):**
    *   Generate a **Mermaid Sequence Diagram or Activity Diagram** for ALL critical flows. Choose the diagram type that best represents the flow. Be precise with object and method names.
    *   **Sequence Diagram Example:**
        ```mermaid
        sequenceDiagram
            participant User
            participant SalesOrderPage as Page "Sales Order"
            participant PricingCodeunit as Codeunit "Custom Pricing"
            participant CustomerTable as Table Customer

            User->>SalesOrderPage: Clicks 'Calculate Special Price'
            SalesOrderPage->>PricingCodeunit: CalculatePrice(SalesLine)
            PricingCodeunit->>CustomerTable: Get(CustNo)
            CustomerTable-->>PricingCodeunit: CustomerRecord
            PricingCodeunit-->>SalesOrderPage: UpdatedPrice
            SalesOrderPage-->>User: Displays new price
        ```
    *   **Activity Diagram Example:**
        ```mermaid
        graph TD
            A[Start] --> B{Order Submitted?};
            B -- Yes --> C[Validate Order Data];
            C --> D{All Valid?};
            D -- Yes --> E[Process Payment];
            E --> F[Update Inventory];
            F --> G[Notify Customer];
            G --> H[End];
            D -- No --> I[Report Validation Errors];
            I --> H;
            B -- No --> H;
        ```

**VI. Eventing Model and Extensibility (`aidocs/06_eventing_extensibility.md`):**

1.  **Published Events:**
    *   List all custom business events and integration events published by this extension. For each event:
        *   Provide the event publisher procedure signature (including its parameters).
        *   Explain the purpose of the event and when it is raised.
        *   Indicate if it's a business event or integration event.
2.  **Subscribed Events:**
    *   List all event subscribers defined in this extension. For each subscriber:
        *   Specify the `ObjectType`, `ObjectNumber/Name`, `EventName`, and `EventPublisherElement` it subscribes to.
        *   Provide the subscriber procedure signature.
        *   Explain the purpose of the subscriber and what actions it performs.
3.  **Interfaces:**
    *   List any interfaces defined or implemented within the project. For each interface:
        *   List its methods.
        *   Explain its purpose.
    *   List the codeunits or other objects that implement these interfaces.
4.  **API Pages/Queries:**
    *   List any pages or queries exposed as APIs (check `APIPublisher`, `APIGroup`, `APIVersion`, `EntityName`, `EntitySetName` properties).
    *   For each, describe its purpose and the data it exposes/manipulates.
5.  **Other Extension Points:**
    *   Identify any other mechanisms designed for extending the functionality of this extension (e.g., specific setup tables that control behavior, facade codeunits intended for external calls, abstract classes meant to be subclassed if applicable in AL patterns).

**VII. Integrations (`aidocs/07_integrations.md`):**

1.  **External System Integrations:**
    *   Identify any code that interacts with external systems. Look for usage of `HttpClient`, `HttpRequestMessage`, `HttpResponseMessage`, `XmlHttp`, `WebService`, `DotNet` interop for external libraries, or file import/export routines for specific formats (XML, JSON, CSV) that suggest external data exchange.
    *   For each identified integration point:
        *   Describe the purpose of the integration.
        *   Identify the external system if possible.
        *   Specify the communication method/protocol (e.g., REST API, SOAP, file transfer).
        *   Mention any authentication methods used (e.g., OAuth, Basic Auth, API Keys in HttpHeaders).
        *   List the key AL objects involved in the integration.
2.  **Internal Integrations (with other BC Apps/Modules):**
    *   Describe any significant integrations with other Business Central apps or standard modules beyond simple data lookups. This might involve subscribing to events from other apps, calling their exposed APIs, or extending their objects in complex ways.

**VIII. Code Quality and Best Practices Assessment (`aidocs/08_code_quality.md`):**

1.  **Adherence to CodeCop/AppSourceCop Rules (Inferred):**
    *   Based on your analysis, comment on the general adherence to common CodeCop and AppSourceCop rules (even if a ruleset isn't explicitly found). For example:
        *   Use of `TextConst` for UI messages and errors.
        *   Proper use of `Commit` (avoiding it in loops or event subscribers that shouldn't commit).
        *   Correct variable initialization and scope.
        *   Avoiding `WITH` statements.
        *   Correct use of `SetAutoCalcFields`.
    *   Highlight areas where deviations are common.
2.  **Error Handling:**
    *   Describe the common error handling strategies. Is `Error(...)` used consistently? Is there use of `TryFunction` or `Confirm`/`StrMenu` for user interactions during errors? Are error messages user-friendly and informative?
3.  **Performance Considerations (Inferred):**
    *   Identify any code patterns that might lead to performance issues:
        *   Inefficient SIFT/CALCFIELDS usage (e.g., `CALCFIELDS` on many fields when only a few are needed, or inside loops).
        *   Record iteration without appropriate `SetCurrentKey` and filters.
        *   Excessive database calls within loops.
        *   Locking issues (e.g., `LOCKTABLE` usage, long-running transactions).
    *   Provide specific examples.
4.  **Security Considerations (Inferred):**
    *   Identify any potential security concerns:
        *   Lack of permission checks where necessary (`TestField` on sensitive operations, or explicit permission set checks).
        *   Hardcoded secrets or sensitive data (though Copilot should be careful with this).
        *   SQL injection possibilities if dynamic query building is used improperly (rare in AL but check any `FilterGroup` or complex filter string constructions).
        *   Insecure API usage (e.g., HTTP instead of HTTPS, weak authentication).
5.  **Testability (Inferred):**
    *   Comment on the apparent testability of the code. Are there dedicated test libraries or test codeunits? Is logic separated in a way that facilitates unit testing (e.g., business logic in codeunits separate from UI logic in pages)?

**IX. Suggested Diagrams (Beyond ERD and Flows) (`aidocs/09_suggested_diagrams.md`):**

1.  Based on your comprehensive analysis, suggest 3-5 *additional* diagram types (beyond the ERD and Flow Diagrams already mandated) that would be particularly beneficial for understanding *this specific codebase*. For each suggestion:
    *   **Diagram Type:** (e.g., State Diagram, Deployment Diagram (conceptual), Data Flow Diagram for a specific complex process not covered).
    *   **Rationale:** Explain *precisely why* this diagram type would be valuable for *this* project, what specific insights it would offer, and which part of the system it should focus on.
    *   **Mermaid Syntax (if feasible):** If you can, provide a basic Mermaid syntax example for the suggested diagram, illustrating the concept for this project.

**X. Onboarding Summary and Next Steps (`aidocs/10_onboarding_summary.md`):**

1.  **Key Strengths of the Codebase:** Briefly list 2-3 notable strengths (e.g., well-structured, good use of events, clear naming).
2.  **Areas for Attention/Improvement:** Briefly list 2-3 areas that a new developer should be particularly mindful of or that could be candidates for future refactoring (based on your findings in architecture, code quality, etc.).
3.  **Recommended First Steps for a New Developer:** Suggest 2-3 specific areas or modules a new developer should focus on first to get acquainted with the codebase, based on its structure and criticality.

**XI. Documentation Index (`aidocs/index.md`):**

1.  **Main Entry Point:** Create an index.md file that serves as the main entry point for all documentation.
2.  **Content Requirements:**
    *   **Title and Introduction:** Include a title and brief introduction to the extension, summarizing its purpose, target audience, and business value.
    *   **Table of Contents:** Create a table of contents with links to all 10 documentation files (01_project_overview.md through 10_onboarding_summary.md).
    *   **Document Descriptions:** For each document in the table of contents, provide a short description (1-2 sentences) explaining what information that document contains.
    *   **Usage Guidance:** Include a section explaining how different roles should use the documentation:
        *   New Developers: Which documents to read first and in what order
        *   Experienced Developers: How to use the documentation as a reference
        *   Architects and Technical Leads: Which sections focus on architecture and design decisions
        *   Project Managers: Which sections provide high-level understanding of functionality

**Output Format and Structure:**

*   All documentation must be in **Markdown format**.
*   Create a root folder named `aidocs`.
*   Inside `aidocs`, create the specified Markdown files (e.g., `01_project_overview.md`, `02_codebase_structure.md`, etc.).
*   Use clear, detailed, and professional prose. Avoid overly terse or bullet-point-only descriptions for narrative sections; use full paragraphs.
*   Use Markdown tables for structured lists where appropriate (e.g., list of objects, list of events).
*   All Mermaid diagrams must be enclosed in ` ```mermaid ... ``` ` blocks.
*   Ensure all file paths and object names mentioned are accurate according to the codebase.
*   Add navigation links at the bottom of each documentation file:
    *   Separate navigation links from the main content with a horizontal rule.
    *   Include appropriate navigation links based on document position:
        * First document: Include "Next" and "Back to Index" links
        * Middle documents: Include "Previous", "Next", and "Back to Index" links
        * Last document: Include "Previous" and "Back to Index" links
    *   Ensure all links correctly point to the appropriate markdown files

**Final Instruction:** Review all generated documentation for accuracy, completeness against these instructions, and clarity before considering the task complete. The goal is to produce a high-quality, deeply insightful, and immediately useful onboarding package.