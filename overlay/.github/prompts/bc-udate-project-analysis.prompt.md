---
mode: 'agent'
---
## GitHub Copilot Prompt for Updating AL Project Documentation (Business Central)

**Objective:** Update and maintain the existing comprehensive documentation for the AL codebase in the `.aidocs` folder. Your primary goal is to ensure the documentation remains accurate, complete, and current as the project evolves. Analyze changes since the last documentation update and systematically refresh all affected sections while preserving the established structure and detail level. This documentation must continue to serve as a comprehensive onboarding guide and reference for developers working with this specific codebase.

**Core Instructions for Copilot - Perform Incremental Documentation Updates:**

Your update process should be thorough yet efficient. Compare the current codebase state with the existing documentation to identify changes, additions, deletions, and modifications. Focus on maintaining accuracy while preserving the depth and quality of the original analysis. Refer to established AL development best practices when evaluating new or modified code.

## Update Process Overview

1. **Analysis Phase:** Compare current codebase with existing documentation to identify changes
2. **Impact Assessment:** Determine which documentation sections are affected by identified changes
3. **Systematic Update:** Refresh all affected sections while maintaining consistency and quality
4. **Validation Phase:** Ensure all cross-references, diagrams, and navigation remain accurate

## Detailed Update Instructions by Section

### **I. Project Overview Updates (`.aidocs/01_project_overview.md`):**

**Change Detection:**
- Compare current `app.json` with documented values for: `id`, `name`, `publisher`, `version`, `brief`, `description`, `privacyStatement`, `EULA`, `help`, `url`, `logo`, `dependencies`, `screenshots`, `platform`, `application`, `idRanges`, `runtime`, `features`
- Identify any changes in project purpose or business domain based on new objects or modifications
- Check for changes in Business Central version compatibility requirements

**Update Actions:**
- Update all changed project metadata
- Revise business domain description if new functionality suggests scope changes
- Update compatibility information if platform/application versions changed
- Refresh development environment settings if `.vscode/settings.json` or ruleset files were modified
- Update analyzer configurations if new tools or rules were added

### **II. Codebase Structure Updates (`.aidocs/02_codebase_structure.md`):**

**Change Detection:**
- Scan for new folders or reorganization within the `src` directory
- Identify new file naming patterns or deviations from established conventions
- Check for new object types or naming conventions in recently added objects
- Analyze variable and method naming in new or modified code

**Update Actions:**
- Update folder structure description if organization changed
- Add examples of any new naming patterns discovered
- Update object naming convention analysis with new examples
- Refresh variable and method naming assessment based on recent code
- Update code formatting analysis if new formatting patterns are observed
- Revise internal object structure assessment with new representative examples

### **III. Architectural Updates (`.aidocs/03_architecture.md`):**

**Change Detection:**
- Identify new modules/components added to the system
- Detect changes in component interactions or dependencies
- Look for new design patterns implemented in recent code
- Check for resolution of previously identified architectural concerns
- Identify any new architectural anti-patterns

**Update Actions:**
- Add new modules/components with their purpose and key objects
- Update component interaction descriptions and dependencies
- Refresh the Mermaid Component Diagram to reflect current architecture
- Document new design patterns with specific examples from recent code
- Update architectural concerns section, removing resolved issues and adding new ones
- Provide updated examples for all identified patterns and anti-patterns

### **IV. Data Model Updates (`.aidocs/04_data_model.md`):**

**Change Detection:**
- Identify new tables, table extensions, or significant field additions
- Detect changes in table relationships or new relationships
- Look for new enums, option fields, or modifications to existing ones
- Check for changes in data validation patterns

**Update Actions:**
- Add new tables to the core entities list with their primary keys and significant fields
- Update relationship descriptions for modified or new relationships
- Regenerate the Mermaid ER Diagram to include new entities and relationships
- Update the separate ERD for standard table extensions if applicable
- Add new enums and option fields with their values and meanings
- Update data validation logic patterns with new examples

### **V. Key Functionalities Updates (`.aidocs/05_key_flows.md`):**

**Change Detection:**
- Identify new business processes or workflows implemented
- Detect modifications to existing workflows
- Look for changes in entry points, sequence of operations, or decision points
- Check for new user interaction patterns

**Update Actions:**
- Add documentation for new core processes with complete flow analysis
- Update existing process documentation with any modifications
- Refresh entry points, sequence of operations, data transformations, and decision points
- Update user interaction descriptions for modified workflows
- Regenerate or create new Mermaid diagrams (Sequence or Activity) for all modified flows
- Ensure all object and method names in diagrams are accurate and current

### **VI. Eventing and Extensibility Updates (`.aidocs/06_eventing_extensibility.md`):**

**Change Detection:**
- Identify new published events (business events and integration events)
- Look for new event subscribers
- Check for new interfaces defined or implemented
- Detect new API pages/queries or modifications to existing ones
- Identify new extension points or mechanisms

**Update Actions:**
- Add new published events with complete signatures, purposes, and event types
- Add new event subscribers with object specifications and procedure signatures
- Update interface documentation with new interfaces and their implementations
- Add or update API pages/queries with their purposes and exposed data
- Document any new extension points or mechanisms for extending functionality
- Update all existing entries if their implementations have changed

### **VII. Integration Updates (`.aidocs/07_integrations.md`):**

**Change Detection:**
- Look for new external system integrations
- Identify changes to existing integration patterns
- Check for new internal integrations with other BC apps/modules
- Detect changes in authentication methods or communication protocols

**Update Actions:**
- Document new external system integrations with complete details
- Update existing integration documentation with any modifications
- Add new internal integrations beyond simple data lookups
- Update communication methods, authentication approaches, and involved AL objects
- Ensure all integration points are accurately documented with current information

### **VIII. Code Quality Updates (`.aidocs/08_code_quality.md`):**

**Change Detection:**
- Assess current adherence to CodeCop/AppSourceCop rules in new/modified code
- Evaluate error handling strategies in recent implementations
- Identify new performance considerations or improvements
- Check for new security considerations
- Assess testability improvements or new testing patterns

**Update Actions:**
- Update adherence assessment based on recent code quality
- Refresh error handling strategy description with new examples
- Add new performance considerations or update existing ones with specific examples
- Update security considerations with any new concerns or improvements
- Refresh testability assessment based on current code organization and test implementations

### **IX. Suggested Diagrams Updates (`.aidocs/09_suggested_diagrams.md`):**

**Change Detection:**
- Evaluate if previously suggested diagrams are still relevant
- Identify new areas that would benefit from additional diagram types
- Check if system complexity changes warrant different visualization approaches

**Update Actions:**
- Remove suggestions that are no longer relevant due to system changes
- Add new diagram suggestions based on evolved complexity or new functionality
- Update rationales to reflect current system state and challenges
- Provide updated Mermaid syntax examples that reflect current objects and relationships

### **X. Onboarding Summary Updates (`.aidocs/10_onboarding_summary.md`):**

**Change Detection:**
- Assess if previously identified strengths are still valid
- Check if previous areas for improvement have been addressed
- Evaluate if recommended first steps for new developers are still optimal

**Update Actions:**
- Update key strengths based on recent improvements or changes
- Refresh areas for attention, removing resolved issues and adding new concerns
- Update recommended first steps based on current system complexity and critical areas
- Ensure recommendations reflect the current state of the codebase and its priorities

### **XI. Documentation Index Updates (`.aidocs/index.md`):**

**Change Detection:**
- Check if the project introduction still accurately reflects the system
- Verify that document descriptions match current content
- Ensure usage guidance remains relevant for different roles

**Update Actions:**
- Update title and introduction to reflect any changes in project scope or purpose
- Refresh document descriptions to accurately reflect updated content
- Update usage guidance if new sections or significant content changes affect how different roles should consume the documentation
- Ensure all links to documentation files remain accurate

## Update Methodology and Quality Assurance

### **Change Identification Process:**
1. **File System Scan:** Compare current file structure with documented structure
2. **Object Analysis:** Identify new, modified, or deleted AL objects
3. **Content Comparison:** Compare existing documentation sections with current code reality
4. **Cross-Reference Validation:** Ensure all object references, file paths, and relationships remain accurate

### **Incremental Update Approach:**
1. **Preserve Quality:** Maintain the same level of detail and professional writing style
2. **Consistency Check:** Ensure new content matches the tone and format of existing documentation
3. **Cross-Section Updates:** When updating one section, check for impacts on other sections
4. **Diagram Accuracy:** Regenerate all diagrams that include modified elements

### **Validation Requirements:**
1. **Accuracy Verification:** All mentioned objects, files, and relationships must exist and be correctly described
2. **Completeness Check:** Ensure no significant changes have been overlooked
3. **Navigation Updates:** Verify all internal links and navigation elements work correctly
4. **Diagram Synchronization:** Ensure all Mermaid diagrams accurately represent current state

## Output Format and Update Standards

### **File Management:**
- Update existing files in the `.aidocs` folder rather than creating new ones
- Preserve the established file naming convention (01_project_overview.md through 10_onboarding_summary.md and index.md)
- Maintain existing Markdown formatting standards and structure

### **Content Standards:**
- Preserve the professional writing style and detailed analysis approach
- Maintain use of Markdown tables for structured information
- Keep all Mermaid diagrams in properly formatted code blocks
- Ensure new content integrates seamlessly with existing content

### **Change Documentation:**
- When making significant updates, consider adding a brief note about what changed if it would be helpful for readers
- Focus on maintaining currency rather than documenting the change process itself
- Preserve the timeless quality of the documentation

**Final Instruction:** Perform a comprehensive but efficient update of all documentation sections, ensuring the documentation accurately reflects the current state of the codebase while maintaining the high quality and usefulness established in the original analysis. The goal is to keep the documentation as a current, reliable, and valuable resource for anyone working with this AL project.