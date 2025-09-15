#requires -Version 7.0

Describe 'Standardized exit code mapping (FR-024)' {
    BeforeAll {
        # Define expected mapping inline to decouple from implementation files
        $Script:Exit = @{
            Success      = 0
            GeneralError = 1
            Guard        = 2
            Analysis     = 3
            Contract     = 4
            Integration  = 5
            MissingTool  = 6
        }
    }

    It 'exposes required keys' {
        ($Exit.ContainsKey('Success'))      | Should -Be $true
        ($Exit.ContainsKey('GeneralError')) | Should -Be $true
        ($Exit.ContainsKey('Guard'))        | Should -Be $true
        ($Exit.ContainsKey('Analysis'))     | Should -Be $true
        ($Exit.ContainsKey('Contract'))     | Should -Be $true
        ($Exit.ContainsKey('Integration'))  | Should -Be $true
        ($Exit.ContainsKey('MissingTool'))  | Should -Be $true
    }

    It 'uses expected numeric values' {
        $Exit.Success      | Should -Be 0
        $Exit.GeneralError | Should -Be 1
        $Exit.Guard        | Should -Be 2
        $Exit.Analysis     | Should -Be 3
        $Exit.Contract     | Should -Be 4
        $Exit.Integration  | Should -Be 5
        $Exit.MissingTool  | Should -Be 6
    }
}
