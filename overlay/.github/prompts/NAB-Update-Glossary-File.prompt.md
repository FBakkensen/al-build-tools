---
mode: 'agent'
description: 'Update Glossary File'
tools: ['codebase', 'editFiles', 'search', 'nab-al-tools-getTranslatedTextsMap']
---

Check for an existing glossary file named "glossary.tsv" in the Translation folder of the project. If it does not exist, create a new file with that name in the Translation folder. If it exists, update it with new terms and phrases as needed.

For all files matching *.*-*.xlf:

1. Find the target language from the XLF file name.
2. Get all, or at least 2000, translated texts from the tool nab-al-tools-getTranslatedTextsMap to identify terminology and phrases from earlier translations.
3. Identify terminology and phrases that could have challenges in translation.
  - A maximum of 500 terminology and phrases should be identified.
  - Only include terminology that are not already present in the glossary.tsv file.
  - Focus on terminology that are:
    - Specific to the business context.
    - Have multiple meanings or interpretations.
    - Not commonly used in the target language or have no direct translation.
4. Order the identified terms and phrases by the most challenging to translate first.
5. Save the results in the glossary.tsv file.
  - If the file do not exist, create it in the same folder as the xlf files.
  - If the file exist, update it with the new terms and phrases.
    - Do not add duplicates.
    - Confirm that the order of the terms and phrases is maintained, i.e., the most challenging terms are at the top.
6. Format the glossary as a tab separated table (TSV), with the languages in columns. The first column should be English and the last column should be a note that explains the context of the term or phrase in English. Add the target language as another column if not already present.