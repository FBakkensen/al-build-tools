---
mode: 'agent'
description: 'Review translations in XLF Files'
tools: ['codebase', 'search', 'nab-al-tools-getTranslatedTextsByState', 'nab-al-tools-refreshXlf', 'nab-al-tools-saveTranslatedTexts']
---

# Translation Review Guide for XLF Files

## Objective
Review and validate translations in XLF files, ensuring quality, consistency, and adherence to localization standards across all languages.

## Prerequisites
- Access to app.json for application metadata
- Access to glossary.tsv in the Translation folder
- Access to XLF files in the Translations folder
- Available NAB AL Tools: refreshXlf, saveTranslatedTexts, getTranslatedTextsByState

## Review Workflow

1. **Initial Setup**
   - Extract app name from app.json
   - Identify target language from XLF filename
   - Load glossary.tsv for terminology reference

2. **File Processing**
   ```powershell
   # For each *.*-*.xlf in Translations folder:
   nab-al-tools-refreshXlf
   nab-al-tools-getTranslatedTextsByState
   ```

3. **Language Processing Order**
   - For Nordic languages:
      1. Review Danish translations first
      2. Use approved Danish translations as reference for Swedish, Norwegian, and Icelandic

4. **Translation Review Criteria**
   - Maintain exact special characters and formatting
   - Use glossary terms when applicable
   - Ensure consistent terminology
   - Preserve all XML/nested elements
   - Follow target language business terminology standards

5. **Review Process**
   For each translation entry:
   1. Validate against review criteria
   2. If improvements needed:
      - Present suggested changes
      - Confirm changes (Yes/No)
      - Apply approved changes
      - Save with sign-off status using nab-al-tools-saveTranslatedTexts
   3.  If no improvements needed:
      - Inform the user
      - Auto Confirm
      - Save with sign-off status using nab-al-tools-saveTranslatedTexts

6. **Final Verification**
   ```powershell
   nab-al-tools-refreshXlf
   nab-al-tools-getTranslatedTextsByState
   ```

7. **Summary**
   Generate review summary including:
   - Completed reviews
   - Translation challenges
   - Suggested glossary additions
   - Quality improvements made
   - Suggestions to update glossary.tsv if necessary

## Important Notes
    - Review one text at a time
    - Prompt for confirmation before applying changes, one at a time.