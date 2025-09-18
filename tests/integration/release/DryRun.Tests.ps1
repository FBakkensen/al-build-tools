#requires -Version 7.0
Set-StrictMode -Version Latest

Describe 'Release workflow dry run behaviour (T005)' {
    It 'produces artifacts without creating tags or releases' {
        if ($env:ALBT_ENABLE_RELEASE_WORKFLOW_TESTS -ne '1') {
            Set-ItResult -Skip -Because 'Release workflow integration suite disabled unless ALBT_ENABLE_RELEASE_WORKFLOW_TESTS=1.'
            return
        }

        Set-ItResult -Pending -Because 'Release workflow integration pending: Validate dry run artifacts and absence of tags/releases.'
    }
}
