#requires -Version 7.0

. "$PSScriptRoot/_helpers.ps1"

Describe 'Environment isolation (via make)' {
    It 'does not leak invocation-scoped env vars into the parent session' {
        # Ensure the test var is not set in parent env
        if ($env:ALBT_TEST_VAR) { Remove-Item Env:ALBT_TEST_VAR -ErrorAction SilentlyContinue }
        ($null -eq $env:ALBT_TEST_VAR) | Should Be $true

        $fx = New-AppFixture
        # Ensure Makefile uses the app subdir
        (Get-Content -LiteralPath $fx.MakefilePath -Raw) -replace 'APP_DIR := \.', 'APP_DIR := app' | Set-Content -LiteralPath $fx.MakefilePath

        # Invoke make with a temporary env var that should NOT persist afterwards
        $res = Invoke-Make -FixturePath $fx.FixturePath -Target 'help' -Env @{ ALBT_TEST_VAR = 'scoped' }
        $res.ExitCode | Should Be 0

        # Verify the env var did not leak back into this session
        ($null -eq $env:ALBT_TEST_VAR) | Should Be $true
    }

    It 'does not change parent WARN_AS_ERROR env from Makefile/export in child process' {
        # Parent session value
        $old = $env:WARN_AS_ERROR
        try {
            $env:WARN_AS_ERROR = '0'
            $fx = New-AppFixture
            # Ensure Makefile uses the app subdir
            (Get-Content -LiteralPath $fx.MakefilePath -Raw) -replace 'APP_DIR := \.', 'APP_DIR := app' | Set-Content -LiteralPath $fx.MakefilePath

            # Child process (make) exports WARN_AS_ERROR (defaults to 1 in Makefile)
            $res = Invoke-Make -FixturePath $fx.FixturePath -Target 'help'
            $res.ExitCode | Should Be 0

            # Parent should remain as we set it locally (0)
            $env:WARN_AS_ERROR | Should Be '0'
        }
        finally {
            if ($null -ne $old) { $env:WARN_AS_ERROR = $old } else { Remove-Item Env:WARN_AS_ERROR -ErrorAction SilentlyContinue }
        }
    }

    It 'scopes future ALBT_VIA_MAKE guard to child process only (placeholder)' -Skip {
        # Placeholder for when scripts set ALBT_VIA_MAKE during make-invoked runs
        ($null -eq $env:ALBT_VIA_MAKE) | Should Be $true
    }
}
