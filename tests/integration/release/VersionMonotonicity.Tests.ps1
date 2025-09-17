#requires -Version 7.0
Set-StrictMode -Version Latest

Describe 'Release workflow version monotonicity (T009)' {
    It 'aborts when version is not strictly greater than existing tags' {
        if ($env:ALBT_ENABLE_RELEASE_WORKFLOW_TESTS -ne '1') {
            Set-ItResult -Skip -Because 'Release workflow helpers not yet implemented (T019+).'
            return
        }

        throw 'TODO: Validate non-monotonic version handling.'
    }
}
