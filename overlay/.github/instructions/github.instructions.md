---
applyTo: '**'
---
## Using GitHub CLI (`gh`)

When interacting with GitHub, prefer the GitHub CLI (`gh`) for efficient command-line operations, automation, and scripting. One of the primary uses is `gh search` for searching repositories, issues, code, and more. Key instructions:

- **Common Commands**:
  - Issues: `gh issue list`, `gh issue create`, `gh issue view <number>`
  - Other: `gh gist` (manage gists), `gh api` (make API calls), `gh search` (search repositories, issues, code, etc.)

- **Constraints**: Never clone repositories, this is abolutely **CRITICAL** Avoid using `gh repo clone` for cloning repositories; .

- **Best Practices**: Use `gh` for tasks like managing issues, PRs, repos, and workflows to streamline workflows. Never use `gh repo clone` for cloning repositories. For scripting, leverage environment variables and aliases. Refer to the [GitHub CLI manual](https://cli.github.com/manual/) for full documentation.