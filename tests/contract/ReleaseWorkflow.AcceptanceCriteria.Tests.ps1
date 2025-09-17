#requires -Version 7.0
Set-StrictMode -Version Latest

Describe 'Release workflow acceptance criteria contract' {
    BeforeAll {
        $testsRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')
        $repoRootInfo = Resolve-Path -LiteralPath (Join-Path -Path $testsRoot.Path -ChildPath '..')
        $script:RepoRoot = $repoRootInfo.Path
        $script:WorkflowPath = Join-Path -Path $script:RepoRoot -ChildPath '.github/workflows/release-overlay.yml'
        if (-not (Test-Path -LiteralPath $script:WorkflowPath)) {
            throw "Expected workflow file at $script:WorkflowPath"
        }

        $raw = Get-Content -LiteralPath $script:WorkflowPath -Raw
        $script:Workflow = ConvertFrom-Yaml -Yaml $raw
    }

    It 'uses workflow_dispatch as the only trigger (AC-01)' {
        $workflowTriggers = $script:Workflow.on.Keys
        $workflowTriggers | Should -Be @('workflow_dispatch')
    }

    It 'defines required workflow inputs for version, summary, and dry_run (AC-02, AC-07, AC-10)' {
        $inputs = $script:Workflow.on.workflow_dispatch.inputs
        $inputs.Keys | Should -Contain 'version'
        $inputs.version.required | Should -BeTrue
        $inputs.Keys | Should -Contain 'summary'
        $inputs.summary.required | Should -BeTrue
        $inputs.Keys | Should -Contain 'dry_run'
        $inputs.dry_run.type | Should -Be 'boolean'
        $inputs.dry_run.default | Should -BeTrue
    }

    It 'tracks planned validation and packaging steps (AC-03..AC-12 placeholders)' {
        Set-ItResult -Skip -Because 'Workflow steps implemented in later tasks (T019+).'
    }
}
