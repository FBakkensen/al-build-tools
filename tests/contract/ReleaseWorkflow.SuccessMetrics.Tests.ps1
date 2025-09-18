#requires -Version 7.0
Set-StrictMode -Version Latest

Describe 'Release workflow success metrics contract' {
    BeforeAll {
        $testsRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')
        $repoRootInfo = Resolve-Path -LiteralPath (Join-Path -Path $testsRoot.Path -ChildPath '..')
        $script:RepoRoot = $repoRootInfo.Path
        $script:MetricsPath = Join-Path -Path $script:RepoRoot -ChildPath 'specs/006-manual-release-workflow/contracts/success-metrics.md'
        if (-not (Test-Path -LiteralPath $script:MetricsPath)) {
            throw "Expected success metrics artifact at $script:MetricsPath"
        }

        $script:MetricsContent = Get-Content -LiteralPath $script:MetricsPath -Raw
    }

    It 'documents all target metrics for the manual release workflow' {
        $expectedRows = @(
            'Artifact Purity',
            'Hash Verification',
            'Workflow Duration P95',
            'Support Ticket Context Inclusion',
            'Tag Collisions',
            'Internal Leakage Incidents'
        )

        foreach ($row in $expectedRows) {
            $pattern = [Regex]::Escape("| $row |")
            $script:MetricsContent | Should -Match $pattern
        }
    }

    It 'acknowledges future instrumentation for duration and hash tracking' {
        $script:MetricsContent | Should -Match 'lightweight internal log'
        $script:MetricsContent | Should -Match 'maintainers record anomalies'
    }

    It 'includes placeholders for automated collection hooks' {
        Set-ItResult -Skip -Because 'Instrumentation scripts will be introduced with helper implementations (T019+).'
    }
}
