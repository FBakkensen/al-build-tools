---
applyTo: '**'
---
# Build Instructions
- First run pwd to ensure you are in the correct directory where the `al.build.ps1` is located.
- Run `Invoke-Build build` from the workspace root to compile the project.
- The build must finish **without any errors or warnings**. If any warning or error appears in the build output, the task is not complete and must be fixed before proceeding.

# Test Instructions
- First run pwd to ensure you are in the correct directory where the `al.build.ps1` is located.
- Run `Invoke-Build test` from the workspace root to run the tests.
- The tests must finish **without any errors or warnings**. If any warning or error appears in the test output, the task is not complete and must be fixed before proceeding.