#requires -Version 7.0
Set-StrictMode -Version Latest

Describe 'Release workflow hash manifest (T007)' {
    It 'produces per-file hashes and reproducible root hash' {
        if ($env:ALBT_ENABLE_RELEASE_WORKFLOW_TESTS -ne '1') {
            Set-ItResult -Skip -Because 'Release workflow integration suite disabled unless ALBT_ENABLE_RELEASE_WORKFLOW_TESTS=1.'
            return
        }

        Set-ItResult -Pending -Because 'Release workflow integration pending: Validate manifest completeness and root hash reproducibility.'
    }
}
