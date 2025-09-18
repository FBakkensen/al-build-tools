#requires -Version 7.0
Set-StrictMode -Version Latest

Describe 'Release workflow metadata block (T014)' {
    It 'embeds machine-readable JSON block in release notes' {
        if ($env:ALBT_ENABLE_RELEASE_WORKFLOW_TESTS -ne '1') {
            Set-ItResult -Skip -Because 'Release workflow integration suite disabled unless ALBT_ENABLE_RELEASE_WORKFLOW_TESTS=1.'
            return
        }

        Set-ItResult -Pending -Because 'Release workflow integration pending: Validate metadata JSON block structure.'
    }
}
