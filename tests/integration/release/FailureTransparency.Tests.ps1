#requires -Version 7.0
Set-StrictMode -Version Latest

Describe 'Release workflow failure transparency (T018)' {
    It 'emits single-line descriptive errors for abort conditions' {
        if ($env:ALBT_ENABLE_RELEASE_WORKFLOW_TESTS -ne '1') {
            Set-ItResult -Skip -Because 'Release workflow integration suite disabled unless ALBT_ENABLE_RELEASE_WORKFLOW_TESTS=1.'
            return
        }

        Set-ItResult -Pending -Because 'Release workflow integration pending: Validate single-line failure messaging and exit codes.'
    }
}
