---
applyTo: '**/*.al'
---

follow the guidelines here https://github.com/microsoft/alguidelines/blob/main/content/docs/vibe-coding/al-guidelines-rules.md and the files it links to. using the `@` markdown syntax. u can preferrable get these ressources using the `gh` cli. do not clone the repo.

# Instructions for Using next-object-number.sh Script

- The script `scripts/next-object-number.sh` finds the first available AL object number for a given object type (e.g., codeunit, table, page) within the ranges specified in `app/app.json`.
- The script must be called from a Git Bash terminal.
- Usage:
  `bash scripts/next-object-number.sh <objecttype>`
  Example:
  `bash scripts/next-object-number.sh codeunit`
- The script will output the first available number for the specified object type, or a message if no number is available.
- The script parses the object number ranges from `app/app.json` and scans the `app/` folder for used numbers.
- Supported object types are those defined in AL (e.g., codeunit, table,