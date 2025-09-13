---
mode: agent
description: Change the project structure, move the al files to new a new folder structure based on user workflows.
tools: ['codebase', 'runCommands', 'search', 'searchResults', 'terminalLastCommand', 'terminalSelection', 'usages', 'sequentialthinking', 'microsoft_docs_search', 'get_file_contents', 'search_code', 'search_orgs', 'search_repositories', 'search_users']
---
# Implement WorkFlow Structure
This change is for the app in the the `app` folder of the repository.

Move the AL files to a new folder structure based on user workflows. The new structure should be organized by workflow, with each workflow containing its own set of AL files. This will help in managing the codebase more effectively and make it easier to navigate through different workflows.

All Work should be in a new folder named after the workflow it belongs to.

All workflow folders should be placed in the `src\Workflows` folder.

## Example Structure
Search the repo `9altitudes/GTM-BC-9AAdvMan-ProjectBased` using the github mcp for example structure: make a comprehensive research of the structure and how it is implemented in the repo. For an in depth understanding of the structure.

## Steps to Implement the Workflow Structure
1. **Create the `Workflows` Folder**:
    - Navigate to the `src` directory and create a new folder named `Workflows`.
2. **Identify Workflows**:
    - Review the existing AL files and identify distinct workflows. Make sure you fully understand all aspects of each workflow. Each workflow should represent a specific business process or functionality. Typical based on a central page or functionality.
3. **Present suggested workflows**:
    - Present the identified workflows to the user for confirmation before proceeding with the implementation. This ensures that all necessary workflows are captured and nothing is missed.
    - Example workflows could include:
      - Sales Order
      - Purchase Order
      - Inventory Management
      - Customer Management
      - Vendor Management
      - Reporting and Analytics
      - etc.
      - Do not suggest workflows that are not present in the repo.
      - Do not continue until the user confirms the workflows.
4. **Create Workflow Folders**:
    - If the user confirms the workflows, proceed to create a new folder for each workflow within the `Workflows` directory.
    - Ensure that the folder names are descriptive and match the workflows identified.
    - For each identified workflow, create a new folder within the `Workflows` directory. Name each folder according to the workflow it represents (e.g., `SalesOrder`, `PurchaseOrder`, etc.).
5. **Move AL Files**:
    - Move the relevant AL files into their corresponding workflow folders. Ensure that each file is placed in the folder that best represents its functionality.
6. **No Reference issue**:
    - AL do not have any references based on the folder structure, so there is no need to update any references in the AL files.
7. **Update Project Structure Documentation**:
    - Update any project structure documentation to reflect the new folder organization. This will help other developers understand the new structure and locate files easily.
8. **Test the New Structure**:
    - After moving the files, ensure that the project builds successfully with no errors or warnings.

## Additional Considerations
Do not edit any files, only move them to the new structure using terminal commands. The terminal is a powershell 7 terminal, so use powershell commands to move the files.