#requires -Version 7.0
Set-StrictMode -Version Latest

Describe 'Release workflow dry run behaviour (T005)' {
    It 'produces artifacts without creating tags or releases' {
        if ($env:ALBT_ENABLE_RELEASE_WORKFLOW_TESTS -ne '1') {
            Set-ItResult -Skip -Because 'Release workflow helpers not yet implemented (T019+).'
            return
        }

        throw 'TODO: Validate dry run artifacts and absence of tags/releases.'
    }
}
