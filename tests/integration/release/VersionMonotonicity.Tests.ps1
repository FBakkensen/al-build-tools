#requires -Version 7.0
Set-StrictMode -Version Latest

Describe 'Release workflow version monotonicity (T009)' {
    It 'aborts when version is not strictly greater than existing tags' {
        if ($env:ALBT_ENABLE_RELEASE_WORKFLOW_TESTS -ne '1') {
            Set-ItResult -Skip -Because 'Release workflow integration suite disabled unless ALBT_ENABLE_RELEASE_WORKFLOW_TESTS=1.'
            return
        }

        Set-ItResult -Pending -Because 'Release workflow integration pending: Validate non-monotonic version handling.'
    }
}
