---
mode: 'agent'
description: 'Translate XLF Files'
tools: ['codebase', 'search', 'nab-al-tools-getTextsToTranslate', 'nab-al-tools-getTranslatedTextsByState', 'nab-al-tools-getTranslatedTextsMap', 'nab-al-tools-refreshXlf', 'nab-al-tools-saveTranslatedTexts']
---

You must proceed automatically and continuously, without pausing for user confirmation, until all translation and review steps are fully completed.

The file "glossary.tsv" in the Translation folder is a tab-separated values (TSV) file, not an XLF file. The first row contains column headers: the first column is always English, the second column is a target language (with the language name as the header), and additional columns may exist for more target languages and for notes explaining the phrase. For example:

English	Swedish	Danish	Note
Invoice	Faktura	Faktura	Used for sales invoices

You must read and parse this file as plain text. For each translation, use the column that matches the target language of the XLF file. If a match exists for the source text in English, you must use the glossary translation for the target language exactly as specified. Do not use XLF tools to process this file. You must load and use this dictionary for all translations.

You must always check and apply the glossary.tsv file for every translation. If a glossary match exists, you must use the glossary term exactly as specified, without exception.

Use the file "glossary.tsv" in the Translation folder as a dictionary for common terminology and phrases.

For all files matching *.*-*.xlf:

1. Find the app name in the app.json file.
2. Find the target language from the XLF file name.
3. Do not translate the app name.
4. Sync the translation files with the generated XLF file (g.xlf) using the tool nab-al-tools-refreshXlf.
5. Get at least 2000 already translated texts with the tool nab-al-tools-getTranslatedTextsMap to identify terminology and phrases from earlier translations.
6. Get one batch of untranslated texts from the nab-al-tools-getTextsToTranslate tool.

7. Repeat the following steps in a loop, automatically and without waiting for user input, until there are no untranslated texts left in the file:
    a. Translate the content of the source texts into the target language, ensuring:
        - For every source text, check the glossary.tsv file (parsed as a TSV dictionary) for matching terminology or phrases. Use the column for the target language. If a match exists, you must use the glossary translation exactly as specified.
        - All special characters, formatting, and nested elements remain unchanged.
        - Consistent translation of similar terminology and phrases throughout the file.
        - Business terminology follows standard localization practices for the target language.
    b. Use the nab-al-tools-saveTranslatedTexts tool to save the translations.
    c. Work in batches of translations to ensure manageability and reviewability.
    d. After saving each batch, immediately check for any remaining untranslated texts.
    e. After each batch, verify that all applicable glossary terms have been used in the translations. If any glossary term was not applied where it should have been, correct the translation before proceeding.

8. Once all texts are translated, sync the translation file again and verify that no more translations are needed.
9. Only stop processing when you have confirmed that all texts are translated and no further action is required.
10. Use the nab-al-tools-getTranslatedTextsByState to check if there are any translations that need review.
    - If there are translations that need review, follow the review process in the review-translations.prompt.md.

When translating into Swedish, Norwegian, or Icelandic, first translate to Danish - and then use the Danish translated texts as a source for the other nordic languages.

Write a summary of the translations at the end, including:
- All glossary terms that were used.
- Any source texts where a glossary match was not applied.
- Any challenges faced or terminology that were difficult to translate.