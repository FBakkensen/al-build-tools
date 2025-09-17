#requires -Version 7.0
Set-StrictMode -Version Latest

Describe 'Release workflow dirty overlay detection (T011)' {
    It 'aborts when overlay contains uncommitted or untracked files' {
        if ($env:ALBT_ENABLE_RELEASE_WORKFLOW_TESTS -ne '1') {
            Set-ItResult -Skip -Because 'Release workflow helpers not yet implemented (T019+).'
            return
        }

        throw 'TODO: Validate overlay cleanliness gate.'
    }
}
