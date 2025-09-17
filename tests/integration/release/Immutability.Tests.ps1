#requires -Version 7.0
Set-StrictMode -Version Latest

Describe 'Release workflow immutability (T015)' {
    It 'fails when re-running with identical version after success' {
        if ($env:ALBT_ENABLE_RELEASE_WORKFLOW_TESTS -ne '1') {
            Set-ItResult -Skip -Because 'Release workflow helpers not yet implemented (T019+).'
            return
        }

        throw 'TODO: Validate immutability guard for repeated version runs.'
    }
}
