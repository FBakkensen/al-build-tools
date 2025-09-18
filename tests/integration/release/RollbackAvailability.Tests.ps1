#requires -Version 7.0
Set-StrictMode -Version Latest

Describe 'Release workflow rollback availability (T017)' {
    It 'keeps previous release asset downloadable after new publish' {
        if ($env:ALBT_ENABLE_RELEASE_WORKFLOW_TESTS -ne '1') {
            Set-ItResult -Skip -Because 'Release workflow integration suite disabled unless ALBT_ENABLE_RELEASE_WORKFLOW_TESTS=1.'
            return
        }

        Set-ItResult -Pending -Because 'Release workflow integration pending: Validate rollback availability of previous release artifacts.'
    }
}
