#requires -Version 7.0
Set-StrictMode -Version Latest

Describe 'Release workflow tag collisions (T010)' {
    It 'aborts when tag already exists' {
        if ($env:ALBT_ENABLE_RELEASE_WORKFLOW_TESTS -ne '1') {
            Set-ItResult -Skip -Because 'Release workflow helpers not yet implemented (T019+).'
            return
        }

        throw 'TODO: Validate tag collision detection before packaging.'
    }
}
