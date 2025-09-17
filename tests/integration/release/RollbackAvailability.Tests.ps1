#requires -Version 7.0
Set-StrictMode -Version Latest

Describe 'Release workflow rollback availability (T017)' {
    It 'keeps previous release asset downloadable after new publish' {
        if ($env:ALBT_ENABLE_RELEASE_WORKFLOW_TESTS -ne '1') {
            Set-ItResult -Skip -Because 'Release workflow helpers not yet implemented (T019+).'
            return
        }

        throw 'TODO: Validate rollback availability of previous release artifacts.'
    }
}
