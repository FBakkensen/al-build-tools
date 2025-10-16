#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$Url = 'https://api.github.com/repos/FBakkensen/al-build-tools',
    [string]$Ref,
    [string]$Dest = '.',
    [string]$Source = 'overlay',
    [int]$HttpTimeoutSec = 0,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArguments
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $IsWindows) {
    $linuxInstaller = Join-Path $PSScriptRoot 'install-linux.ps1'
    if (Test-Path $linuxInstaller) {
        & $linuxInstaller @PSBoundParameters
        return
    }
    Write-Error "Installation failed: Windows installer invoked on a non-Windows platform. Run install-linux.ps1 instead."
}

    # FR-008: Reject unsupported parameters (usage guard)
if (-not (Get-Variable -Name 'args' -Scope 0 -ErrorAction SilentlyContinue)) {
    $scriptArgs = @()
} else {
    $scriptArgs = $args
}
$unknownArgs = @()
if ($RemainingArguments) {
    $unknownArgs += $RemainingArguments
}
if ($scriptArgs -and $scriptArgs.Count -gt 0) {
    $unknownArgs += $scriptArgs
}
if ($unknownArgs.Count -gt 0) {
    $firstArg = $unknownArgs[0]
    $argName = if ($firstArg.StartsWith('-')) { $firstArg.Substring(1) } else { $firstArg }
    Write-Host "[install] guard UnknownParameter argument=`"$argName`""
    Write-Host "Usage: Install-AlBuildTools [-Url <url>] [-Ref <ref>] [-Dest <path>] [-Source <folder>]"
    Write-Error "Installation failed: Unknown parameter '$argName'. Use: Install-AlBuildTools [-Url <url>] [-Ref <ref>] [-Dest <path>] [-Source <folder>]"
}

# Standardized output functions (matching common.psm1 style)
function Write-BuildMessage {
    param(
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Step', 'Detail')]
        [string]$Type = 'Info',
        [Parameter(Mandatory=$true)]
        [string]$Message
    )
    switch ($Type) {
        'Info'    { Write-Host "[INFO] " -NoNewline -ForegroundColor Cyan; Write-Host $Message }
        'Success' { Write-Host "[✓] " -NoNewline -ForegroundColor Green; Write-Host $Message }
        'Warning' { Write-Host "[!] " -NoNewline -ForegroundColor Yellow; Write-Host $Message }
        'Error'   { Write-Host "[✗] " -NoNewline -ForegroundColor Red; Write-Host $Message }
        'Step'    { Write-Host "[→] " -NoNewline -ForegroundColor Magenta; Write-Host $Message }
        'Detail'  { Write-Host "    • " -NoNewline -ForegroundColor Gray; Write-Host $Message -ForegroundColor Gray }
    }
}

function Write-BuildHeader {
    param([Parameter(Mandatory=$true)][string]$Title)
    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor DarkGray
    Write-Host "  $Title" -ForegroundColor White
    Write-Host ("=" * 80) -ForegroundColor DarkGray
    Write-Host ""
}

$script:AutoInstallPrereqs = $false
if ($env:ALBT_AUTO_INSTALL -and $env:ALBT_AUTO_INSTALL.ToString().ToLowerInvariant() -in @('1','true','yes')) {
    $script:AutoInstallPrereqs = $true
}

function Get-ChocolateyExecutable {
    $candidates = @()
    if ($env:ProgramData) { $candidates += Join-Path $env:ProgramData 'chocolatey\bin\choco.exe' }
    if ($env:ProgramFiles) { $candidates += Join-Path $env:ProgramFiles 'chocolatey\bin\choco.exe' }
    $programFilesX86 = ${env:ProgramFiles(x86)}
    if ($programFilesX86) { $candidates += Join-Path $programFilesX86 'chocolatey\bin\choco.exe' }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    $command = Get-Command choco -ErrorAction SilentlyContinue
    if ($command) { return $command.Path }

    return $null
}

function Install-Chocolatey {
    Write-Host "[install] prerequisite tool=`"choco`" status=`"installing`""
    Write-BuildMessage -Type Info -Message "Installing Chocolatey..."

    $installScript = 'https://community.chocolatey.org/install.ps1'
    $processArgs = "Set-ExecutionPolicy Bypass -Scope Process -Force; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; iex ((New-Object System.Net.WebClient).DownloadString(`'$installScript`'))"

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell'
    $psi.Arguments = "-NoLogo -NoProfile -Command $processArgs"
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardOutput = $true
    $psi.UseShellExecute = $false

    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()

    if ($stdout) { Write-Verbose "[install] choco install stdout: $stdout" }
    if ($stderr) { Write-Verbose "[install] choco install stderr: $stderr" }

    if ($proc.ExitCode -ne 0) {
        throw "Chocolatey installation failed with exit code $($proc.ExitCode)"
    }
}

function Ensure-Chocolatey {
    $chocoPath = Get-ChocolateyExecutable
    if ($chocoPath) {
        return $chocoPath
    }

    if (-not $script:AutoInstallPrereqs) {
        $approved = Confirm-Installation -ToolName 'Chocolatey' -Purpose 'Installing Git and .NET SDK prerequisites'
        if (-not $approved) {
            Write-Host "[install] guard MissingPrerequisite tool=`"choco`" declined=true"
            Write-Error 'Installation failed: Chocolatey is required to install prerequisites. Please install Chocolatey from https://chocolatey.org/install and retry.'
        }
    }

    Install-Chocolatey

    $chocoPath = Get-ChocolateyExecutable
    if (-not $chocoPath) {
        Write-Error 'Installation failed: Chocolatey installation completed but choco.exe was not found on disk.'
    }

    try {
        $proc = Start-Process -FilePath $chocoPath -ArgumentList 'feature','enable','-n=allowGlobalConfirmation' -NoNewWindow -Wait -PassThru
        if ($proc.ExitCode -ne 0) {
            Write-Verbose "[install] Failed to enable allowGlobalConfirmation (exit $($proc.ExitCode))"
        }
    } catch {
        Write-Verbose "[install] Unable to enable Chocolatey allowGlobalConfirmation: $($_.Exception.Message)"
    }

    return $chocoPath
}

function Invoke-ChocolateyCommand {
    param(
        [Parameter(Mandatory=$true)][string[]]$Arguments
    )

    $chocoPath = Ensure-Chocolatey
    $chocoArgs = $Arguments + @('--no-progress')
    $proc = Start-Process -FilePath $chocoPath -ArgumentList $chocoArgs -NoNewWindow -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        throw "Chocolatey command '$($Arguments -join ' ')'' exited with code $($proc.ExitCode)"
    }
}

function Test-Git {
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    return [bool]$gitCmd
}

function Install-Git {
    Write-Host "[install] prerequisite tool=`"git`" status=`"installing`""
    Write-BuildMessage -Type Info -Message "Installing Git via Chocolatey..."
    Invoke-ChocolateyCommand -Arguments @('install','git','--yes')
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitCmd) {
        throw 'Git installation completed but git.exe not found in PATH.'
    }
    return $true
}

function Ensure-Git {
    if (Test-Git) {
        $gitVersion = (& git --version 2>$null)
        if ($gitVersion) {
            Write-Host "[install] prerequisite tool=`"git`" status=`"present`" version=$gitVersion"
        } else {
            Write-Host "[install] prerequisite tool=`"git`" status=`"present`""
        }
        return $true
    }

    if (-not $script:AutoInstallPrereqs) {
        $approve = Confirm-Installation -ToolName 'Git' -Purpose 'Managing repository overlays during installation'
        if (-not $approve) {
            Write-Host "[install] guard MissingPrerequisite tool=`"git`" declined=true"
            Write-Error 'Installation failed: Git is required to manage the destination repository.'
        }
    }

    Install-Git
    return $true
}

# Legacy functions for backward compatibility with diagnostics
function Write-Step($n, $msg) {
    Write-BuildMessage -Type Step -Message $msg
    # Emit standardized step diagnostic for cross-platform parity testing
    $stepName = $msg -replace '[^\w\s]', '' -replace '\s+', '_' -replace '^_|_$', ''
    Write-Host ("[install] step index={0} name={1}" -f $n, $stepName)
}

function ConvertTo-CanonicalReleaseTag {
    param(
        [string]$Tag
    )

    if ([string]::IsNullOrWhiteSpace($Tag)) {
        return $Tag
    }

    $trimmed = $Tag.Trim()
    if ($trimmed.Length -gt 1 -and ($trimmed[0] -eq 'v' -or $trimmed[0] -eq 'V') -and [char]::IsDigit($trimmed[1])) {
        return 'v' + $trimmed.Substring(1)
    }

    if ($trimmed.Length -gt 0 -and [char]::IsDigit($trimmed[0])) {
        return 'v' + $trimmed
    }

    return $trimmed
}

function Resolve-EffectiveReleaseTag {
    param(
        [string]$ParameterRef,
        [string]$EnvRelease,
        [bool]$EmitVerboseNote = $false
    )

    if (-not [string]::IsNullOrWhiteSpace($ParameterRef)) {
        return [pscustomobject]@{
            Tag = ConvertTo-CanonicalReleaseTag -Tag $ParameterRef
            Source = 'Parameter'
            Original = $ParameterRef
            NoteMessage = $null
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($EnvRelease)) {
        $canonical = ConvertTo-CanonicalReleaseTag -Tag $EnvRelease
        Write-Verbose "Using env ALBT_RELEASE=$canonical"
        $noteMessage = $null
        if ($EmitVerboseNote) {
            $noteMessage = "[install] note Using env ALBT_RELEASE=$canonical"
        }
        return [pscustomobject]@{
            Tag = $canonical
            Source = 'Environment'
            Original = $EnvRelease
            NoteMessage = $noteMessage
        }
    }

    return [pscustomobject]@{
        Tag = $null
        Source = 'Latest'
        Original = $null
        NoteMessage = $null
    }
}

function Get-HttpStatusCodeFromError {
    param(
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    if ($null -eq $ErrorRecord) { return $null }

    $exception = $ErrorRecord.Exception
    while ($exception) {
        $response = $null
        try { $response = $exception.Response } catch { $response = $null }
        if ($response) {
            $statusCandidate = $null
            try { $statusCandidate = $response.StatusCode } catch { $statusCandidate = $null }
            if ($null -ne $statusCandidate) {
                try {
                    return [int]$statusCandidate
                } catch {
                    Write-Verbose "[install] Failed to convert status candidate to int: $($_.Exception.Message)"
                }
            }
        }

        $status = $null
        try { $status = $exception.StatusCode } catch { $status = $null }
        if ($null -ne $status) {
            if ($status -is [int]) { return $status }
            if ($status -is [System.Net.HttpStatusCode]) { return [int]$status }

            $valueCandidate = $null
            try { $valueCandidate = $status.value__ } catch { $valueCandidate = $null }
            if ($valueCandidate -is [int]) { return $valueCandidate }
        }

        $exception = $exception.InnerException
    }

    return $null
}

function Resolve-DownloadFailureDetails {
    param(
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        [string]$DefaultHint = 'Check network connectivity and repository URL',
        [hashtable]$StatusHints
    )

    $category = 'Unknown'
    $hint = $DefaultHint

    if ($null -eq $ErrorRecord) {
        return [pscustomobject]@{ Category = $category; Hint = $hint }
    }

    $message = $ErrorRecord.Exception.Message
    $statusCode = Get-HttpStatusCodeFromError -ErrorRecord $ErrorRecord

    if ($ErrorRecord.Exception -is [System.OperationCanceledException]) {
        return [pscustomobject]@{ Category = 'Timeout'; Hint = 'Request timed out' }
    }

    if ($message -match 'timed out|timeout') {
        return [pscustomobject]@{ Category = 'Timeout'; Hint = 'Request timed out' }
    }

    if ($message -match 'name or service not known|No such host|Temporary failure in name resolution|network is unreachable|connection refused|connect failed|actively refused') {
        return [pscustomobject]@{ Category = 'NetworkUnavailable'; Hint = 'Network connectivity issues' }
    }

    if ($statusCode) {
        if ($StatusHints -and $StatusHints.ContainsKey($statusCode)) {
            $entry = $StatusHints[$statusCode]
            if ($entry -and $entry.Category) { $category = $entry.Category }
            if ($entry -and $entry.Hint) { $hint = $entry.Hint }
        } else {
            switch ($statusCode) {
                404 { $category = 'NotFound'; $hint = 'Resource not found' }
                408 { $category = 'Timeout'; $hint = 'Request timed out' }
                429 { $category = 'Unknown'; $hint = 'Rate limited retrieving resource' }
                500 { $category = 'Unknown'; $hint = 'Server error retrieving resource' }
                502 { $category = 'NetworkUnavailable'; $hint = 'Bad gateway retrieving resource' }
                503 { $category = 'NetworkUnavailable'; $hint = 'Service unavailable' }
                504 { $category = 'Timeout'; $hint = 'Gateway timeout retrieving resource' }
                default { $category = 'Unknown'; $hint = $DefaultHint }
            }
        }
        return [pscustomobject]@{ Category = $category; Hint = $hint }
    }

    return [pscustomobject]@{ Category = $category; Hint = $hint }
}

function Confirm-Installation {
    param(
        [string]$ToolName,
        [string]$Purpose
    )

    if ($script:AutoInstallPrereqs) {
        Write-Verbose "[install] Auto-approving installation for $ToolName"
        return $true
    }

    # Detect non-interactive mode
    $isInteractive = $true
    try {
        if ($null -eq $Host.UI.RawUI -or $Host.Name -eq 'ServerRemoteHost') {
            $isInteractive = $false
        }
    } catch {
        $isInteractive = $false
    }

    if (-not $isInteractive) {
        Write-Verbose "[install] Non-interactive mode detected - skipping prompt for $ToolName"
        return $false
    }

    Write-Host ""
    Write-Host "$ToolName is required for: $Purpose" -ForegroundColor Yellow
    Write-Host "Install $ToolName now? (Y/n): " -NoNewline -ForegroundColor Cyan
    $response = Read-Host

    if ([string]::IsNullOrWhiteSpace($response) -or $response -ieq 'y' -or $response -ieq 'yes') {
        return $true
    }

    return $false
}

function Test-DotNetSdk {
    Write-Verbose "[install] Checking for .NET SDK"
    try {
        $dotnetPath = Get-Command dotnet -ErrorAction SilentlyContinue
        if ($null -eq $dotnetPath) {
            return $false
        }

        $versionOutput = & dotnet --version 2>&1
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($versionOutput)) {
            Write-Verbose "[install] .NET SDK found: version $versionOutput"
            return $true
        }
        return $false
    } catch {
        Write-Verbose "[install] .NET SDK check failed: $($_.Exception.Message)"
        return $false
    }
}

function Install-DotNetSdk {
    Write-Host "[install] prerequisite tool=`"dotnet`" status=`"installing`""
    Write-BuildMessage -Type Info -Message "Installing .NET SDK 8 via Chocolatey..."

    $packageName = 'dotnet-8.0-sdk'
    $additionalArgs = @()
    if ($env:ALBT_DOTNET_PACKAGE_VERSION) {
        $additionalArgs += @('--version', $env:ALBT_DOTNET_PACKAGE_VERSION)
    }

    try {
        Invoke-ChocolateyCommand -Arguments (@('install', $packageName, '--yes') + $additionalArgs)
        Write-Host "[install] prerequisite tool=`"dotnet`" status=`"installed`""
        Write-BuildMessage -Type Success -Message ".NET SDK 8 installed successfully"
        return $true
    } catch {
        Write-Warning "Failed to install .NET SDK via Chocolatey: $($_.Exception.Message)"
        return $false
    }
}

function Test-InvokeBuildModule {
    Write-Verbose "[install] Checking for InvokeBuild module"
    try {
        $module = Get-Module -ListAvailable -Name InvokeBuild -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $module) {
            Write-Verbose "[install] InvokeBuild found: version $($module.Version)"
            return $true
        }
        return $false
    } catch {
        Write-Verbose "[install] InvokeBuild check failed: $($_.Exception.Message)"
        return $false
    }
}

function Install-InvokeBuildModule {
    Write-Host "[install] prerequisite tool=`"InvokeBuild`" status=`"installing`""
    Write-BuildMessage -Type Info -Message "Installing InvokeBuild PowerShell module..."

    try {
        # Ensure PSGallery is trusted
        $psGallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
        if ($null -ne $psGallery -and $psGallery.InstallationPolicy -ne 'Trusted') {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        }

        Install-Module -Name InvokeBuild -Scope CurrentUser -Force -Repository PSGallery -ErrorAction Stop

        Write-Host "[install] prerequisite tool=`"InvokeBuild`" status=`"installed`""
        Write-BuildMessage -Type Success -Message "InvokeBuild module installed successfully"
        return $true
    } catch {
        Write-Warning "Failed to install InvokeBuild module: $($_.Exception.Message)"
        return $false
    }
}

function Test-PowerShellVersion {
    param(
        [System.Version]$MinimumVersion = [System.Version]'7.2'
    )

    $psVersion = if ($env:ALBT_TEST_FORCE_PSVERSION) {
        [System.Version]$env:ALBT_TEST_FORCE_PSVERSION
    } else {
        $PSVersionTable.PSVersion
    }

    Write-Verbose "[install] PowerShell version: $psVersion (minimum required: $MinimumVersion)"
    return $psVersion -ge $MinimumVersion
}

function Install-PowerShell {
    Write-Host "[install] prerequisite tool=`"pwsh`" status=`"installing`""
    Write-BuildMessage -Type Info -Message "Installing PowerShell 7 via Chocolatey..."

    try {
        Invoke-ChocolateyCommand -Arguments @('install','powershell','--yes')
        Write-Host "[install] prerequisite tool=`"pwsh`" status=`"installed`" relaunch_required=true"
        Write-BuildMessage -Type Success -Message "PowerShell 7 installed successfully"
        Write-Host ""
        Write-Host "IMPORTANT: PowerShell 7 has been installed." -ForegroundColor Yellow
        Write-Host "Please close this window and rerun this script in PowerShell 7." -ForegroundColor Yellow
        Write-Host "You can start PowerShell 7 by running: pwsh" -ForegroundColor Cyan
        return $true
    } catch {
        Write-Warning "Failed to install PowerShell via Chocolatey: $($_.Exception.Message)"
        return $false
    }
}

function Install-AlBuildTools {
    [CmdletBinding()]
    param(
        [string]$Url = 'https://api.github.com/repos/FBakkensen/al-build-tools',
        [string]$Ref,
        [string]$Dest = '.',
        [string]$Source = 'overlay',
        [int]$HttpTimeoutSec = 0
    )

    # FR-004: Enforce minimum PowerShell version guard
    $psVersion = if ($env:ALBT_TEST_FORCE_PSVERSION) {
        [System.Version]$env:ALBT_TEST_FORCE_PSVERSION
    } else {
        $PSVersionTable.PSVersion
    }

    Write-Host "[install] prerequisite tool=`"pwsh`" status=`"check`" version=$psVersion"

    if ($psVersion -lt [System.Version]'7.2') {
        Write-Host "[install] prerequisite tool=`"pwsh`" status=`"insufficient`" required=7.2"

        $shouldInstall = Confirm-Installation -ToolName "PowerShell 7.2+" -Purpose "AL Build Tools installation and build operations"

        if ($shouldInstall) {
            $installed = Install-PowerShell
            if ($installed) {
                # PowerShell was installed, but we need to exit and let the user relaunch
                exit 0
            } else {
                Write-Host "[install] guard PowerShellVersionUnsupported version=$psVersion declined=false install_failed=true"
                Write-Error "Installation failed: Could not install PowerShell 7. Please install manually from https://aka.ms/powershell"
            }
        } else {
            Write-Host "[install] guard PowerShellVersionUnsupported version=$psVersion declined=true"
            Write-Error "Installation failed: PowerShell 7.2 or later is required. Current version: $psVersion. Install from https://aka.ms/powershell"
        }
    }

    $effectiveTimeoutSec = $HttpTimeoutSec
    if ($effectiveTimeoutSec -le 0) {
        $envTimeoutRaw = $env:ALBT_HTTP_TIMEOUT_SEC
        if ($envTimeoutRaw) {
            $parsedTimeout = 0
            if ([int]::TryParse($envTimeoutRaw, [ref]$parsedTimeout) -and $parsedTimeout -gt 0) {
                $effectiveTimeoutSec = $parsedTimeout
            } else {
                Write-Warning "[install] env ALBT_HTTP_TIMEOUT_SEC value '$envTimeoutRaw' is not a positive integer; ignoring."
            }
        }
    }

    $startTime = Get-Date
    $step = 0
    $step++; Write-Step $step "Resolve destination"
    try {
        $destFull = (Resolve-Path -Path $Dest -ErrorAction Stop).Path
    } catch {
        # Create the destination if it does not exist, then resolve the actual path
        $created = New-Item -ItemType Directory -Force -Path $Dest
        $destFull = (Resolve-Path -Path $created.FullName).Path
    }
    Write-BuildMessage -Type Info -Message "Install/update from $Url into $destFull (source: $Source)"

    $step++; Write-Step $step "Verify prerequisites"

    Write-Host "[install] prerequisite tool=`"choco`" status=`"check`""
    $chocoPath = Ensure-Chocolatey
    if ($chocoPath) {
        Write-BuildMessage -Type Success -Message "Chocolatey available at $chocoPath"
    }

    Write-Host "[install] prerequisite tool=`"git`" status=`"check`""
    Ensure-Git | Out-Null

    # Check .NET SDK
    Write-Host "[install] prerequisite tool=`"dotnet`" status=`"check`""
    $hasDotNet = Test-DotNetSdk
    if ($hasDotNet) {
        $dotnetVersion = & dotnet --version 2>&1
        Write-Host "[install] prerequisite tool=`"dotnet`" status=`"present`" version=$dotnetVersion"
        Write-BuildMessage -Type Success -Message ".NET SDK is installed (version $dotnetVersion)"
    } else {
        Write-Host "[install] prerequisite tool=`"dotnet`" status=`"missing`""

        $shouldInstall = Confirm-Installation -ToolName ".NET SDK 8" -Purpose "Building AL projects and downloading symbols from NuGet"

        if ($shouldInstall) {
            $installed = Install-DotNetSdk
            if (-not $installed) {
                Write-Host "[install] guard MissingPrerequisite tool=`"dotnet`" declined=false install_failed=true"
                Write-Error "Installation failed: Could not install .NET SDK. Please install manually from https://dotnet.microsoft.com/download"
            }
            Write-BuildMessage -Type Success -Message ".NET SDK is now installed"
        } else{
            Write-Host "[install] guard MissingPrerequisite tool=`"dotnet`" declined=true"
            Write-Error "Installation failed: .NET SDK is required. Install from https://dotnet.microsoft.com/download"
        }
    }

    # Check InvokeBuild module
    Write-Host "[install] prerequisite tool=`"InvokeBuild`" status=`"check`""
    $hasInvokeBuild = Test-InvokeBuildModule
    if ($hasInvokeBuild) {
        $ibModule = Get-Module -ListAvailable -Name InvokeBuild -ErrorAction SilentlyContinue | Select-Object -First 1
        Write-Host "[install] prerequisite tool=`"InvokeBuild`" status=`"present`" version=$($ibModule.Version)"
        Write-BuildMessage -Type Success -Message "InvokeBuild module is installed (version $($ibModule.Version))"
    } else{
        Write-Host "[install] prerequisite tool=`"InvokeBuild`" status=`"missing`""

        $shouldInstall = Confirm-Installation -ToolName "InvokeBuild module" -Purpose "Running build tasks and orchestrating the build process"

        if ($shouldInstall) {
            $installed = Install-InvokeBuildModule
            if (-not $installed) {
                Write-Host "[install] guard MissingPrerequisite tool=`"InvokeBuild`" declined=false install_failed=true"
                Write-Error "Installation failed: Could not install InvokeBuild module. Please install manually with: Install-Module InvokeBuild -Scope CurrentUser"
            }
            Write-BuildMessage -Type Success -Message "InvokeBuild module is now installed"
        } else{
            Write-Host "[install] guard MissingPrerequisite tool=`"InvokeBuild`" declined=true"
            Write-Error "Installation failed: InvokeBuild module is required. Install with: Install-Module InvokeBuild -Scope CurrentUser"
        }
    }

    $step++; Write-Step $step "Detect git repository"
    $gitOk = $false
    try {
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = 'git'
        $pinfo.Arguments = "-C `"$destFull`" rev-parse --git-dir"
        $pinfo.RedirectStandardOutput = $true
        $pinfo.RedirectStandardError = $true
        $pinfo.UseShellExecute = $false
        $p = [System.Diagnostics.Process]::Start($pinfo)
        $p.WaitForExit()
        if ($p.ExitCode -eq 0) { $gitOk = $true }
    } catch {
        Write-Verbose "[install] git check failed: $($_.Exception.Message)"
    }
    # FR-023: Abort when destination is not a git repository
    if (-not $gitOk -and -not (Test-Path (Join-Path $destFull '.git'))) {
        Write-Host "[install] guard GitRepoRequired"
        Write-Error "Installation failed: Destination '$destFull' is not a git repository. Please initialize git first with 'git init' or clone an existing repository."
    }

    # FR-024: Require clean working tree before copying overlay
    if ($gitOk -or (Test-Path (Join-Path $destFull '.git'))) {
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = 'git'
        $pinfo.Arguments = "-C `"$destFull`" status --porcelain"
        $pinfo.RedirectStandardOutput = $true
        $pinfo.RedirectStandardError = $true
        $pinfo.UseShellExecute = $false
        $p = [System.Diagnostics.Process]::Start($pinfo)
        $p.WaitForExit()
        if ($p.ExitCode -eq 0) {
            $statusOutput = $p.StandardOutput.ReadToEnd().Trim()
            if (-not [string]::IsNullOrEmpty($statusOutput)) {
                Write-Host "[install] guard WorkingTreeNotClean"
                Write-Error "Installation failed: Working tree is not clean. Please commit or stash your changes before running the installation."
            }
        }
    }
    Write-BuildMessage -Type Success -Message "Working in: $destFull"

    $tmp = New-Item -ItemType Directory -Path ([System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.IO.Path]::GetRandomFileName()))
    Write-Host "[install] temp workspace=`"$($tmp.FullName)`""
    $selectedReleaseTag = $null
    $assetName = 'overlay.zip'
    $assetDownloadUrl = $null
    $releaseRequestUrl = $null
    $refForFailure = $null
    try {
        $step++; Write-Step $step "Select release"
        $apiBase = $Url.TrimEnd('/')
        $emitVerboseNote = $false
        if ($PSCmdlet) {
            if ($PSCmdlet.MyInvocation.BoundParameters.ContainsKey('Verbose')) { $emitVerboseNote = $true }
        }
        if (-not $emitVerboseNote) {
            if ($VerbosePreference -eq 'Continue' -or $VerbosePreference -eq 'Inquire') {
                $emitVerboseNote = $true
            }
        }

        $selection = Resolve-EffectiveReleaseTag -ParameterRef $Ref -EnvRelease $env:ALBT_RELEASE -EmitVerboseNote:$emitVerboseNote
        $noteProperty = if ($selection) { $selection.PSObject.Properties['NoteMessage'] } else { $null }
        if ($noteProperty -and $selection.NoteMessage) {
            Write-Output $selection.NoteMessage
        }
        $refForFailure = if ($selection.Tag) { $selection.Tag } else { 'latest' }

        if ([string]::IsNullOrWhiteSpace($apiBase)) {
            Write-Host "[install] download failure ref=`"$refForFailure`" url=`"$Url`" category=Unknown hint=`"Release service URL is empty`""
            Write-Error "Installation failed: Release service URL is empty or invalid."
        }

        if ($selection.Tag) {
            $encodedTag = [System.Net.WebUtility]::UrlEncode($selection.Tag)
            $releaseRequestUrl = "$apiBase/releases/tags/$encodedTag"
        } else {
            $releaseRequestUrl = "$apiBase/releases/latest"
        }

        $metadataStatusHints = @{
            401 = @{ Category = 'Unknown'; Hint = 'Authentication required for release metadata' }
            403 = @{ Category = 'Unknown'; Hint = 'Access denied retrieving release metadata' }
            404 = @{ Category = 'NotFound'; Hint = 'Release tag not found' }
        }

        try {
            $metadataRequest = @{
                Uri = $releaseRequestUrl
                Method = 'Get'
                Headers = @{
                    'Accept' = 'application/vnd.github+json'
                    'User-Agent' = 'al-build-tools-installer'
                }
                ErrorAction = 'Stop'
            }
            if ($effectiveTimeoutSec -gt 0) {
                $metadataRequest['TimeoutSec'] = $effectiveTimeoutSec
            }
            $releaseMetadata = Invoke-RestMethod @metadataRequest
        } catch {
            $failure = Resolve-DownloadFailureDetails -ErrorRecord $_ -DefaultHint 'Unable to retrieve release metadata' -StatusHints $metadataStatusHints
            Write-Host "[install] download failure ref=`"$refForFailure`" url=`"$releaseRequestUrl`" category=$($failure.Category) hint=`"$($failure.Hint)`""
            Write-Error "Installation failed: Unable to retrieve release metadata. $($failure.Hint)"
        }

        if ($null -eq $releaseMetadata) {
            Write-Host "[install] download failure ref=`"$refForFailure`" url=`"$releaseRequestUrl`" category=NotFound hint=`"Release metadata missing`""
            Write-Error "Installation failed: Release metadata is missing or invalid."
        }

        $selectedReleaseTag = ConvertTo-CanonicalReleaseTag -Tag ($releaseMetadata.tag_name)
        if (-not $selectedReleaseTag) {
            $selectedReleaseTag = if ($selection.Tag) { $selection.Tag } else { $null }
        }
        if (-not $selectedReleaseTag) {
            Write-Host "[install] download failure ref=`"$refForFailure`" url=`"$releaseRequestUrl`" category=Unknown hint=`"Release tag could not be determined`""
            Write-Error "Installation failed: Release tag could not be determined from the release metadata."
        }
        $refForFailure = $selectedReleaseTag

        if ($releaseMetadata.draft -eq $true -or $releaseMetadata.prerelease -eq $true) {
            Write-Host "[install] download failure ref=`"$refForFailure`" url=`"$releaseRequestUrl`" category=NotFound hint=`"Release not published`""
            Write-Error "Installation failed: Release '$refForFailure' is not published (it may be a draft or prerelease)."
        }

        $assets = @()
        $assetsProperty = $releaseMetadata.PSObject.Properties['assets']
        if ($assetsProperty -and $releaseMetadata.assets) {
            if ($releaseMetadata.assets -is [System.Array]) {
                $assets = $releaseMetadata.assets
            } else {
                $assets = @($releaseMetadata.assets)
            }
        }

        $asset = $null
        $fallbackAsset = $null
        foreach ($candidate in $assets) {
            if ($null -eq $candidate) { continue }
            $nameProp = $candidate.PSObject.Properties | Where-Object { $_.Name -eq 'name' } | Select-Object -First 1
            if (-not $nameProp) { continue }
            $candidateName = [string]$nameProp.Value
            if ([string]::IsNullOrWhiteSpace($candidateName)) { continue }

            if ($candidateName -ieq 'overlay.zip') {
                $asset = $candidate
                break
            }

            if (-not $fallbackAsset -and $candidateName -like 'al-build-tools-*.zip') {
                $fallbackAsset = $candidate
            }
        }

        if (-not $asset) {
            if ($fallbackAsset) {
                $asset = $fallbackAsset
                Write-Verbose "[install] asset fallback Using release asset '$(($fallbackAsset.name))'"
            } else {
                Write-Host "[install] download failure ref=`"$refForFailure`" url=`"$releaseRequestUrl`" category=NotFound hint=`"Release asset overlay.zip not found`""
                Write-Error "Installation failed: Release asset 'overlay.zip' not found in release '$refForFailure'."
            }
        }

        $assetNameProp = $asset.PSObject.Properties | Where-Object { $_.Name -eq 'name' } | Select-Object -First 1
        if ($assetNameProp) {
            $assetName = [string]$assetNameProp.Value
        }

        $assetUrlProp = $asset.PSObject.Properties | Where-Object { $_.Name -eq 'browser_download_url' } | Select-Object -First 1
        if ($assetUrlProp) {
            $assetDownloadUrl = [string]$assetUrlProp.Value
        }

        if ([string]::IsNullOrWhiteSpace($assetDownloadUrl)) {
            Write-Host "[install] download failure ref=`"$refForFailure`" url=`"$releaseRequestUrl`" category=Unknown hint=`"Release asset download URL missing`""
            Write-Error "Installation failed: Release asset download URL is missing or invalid."
        }

        Write-BuildMessage -Type Info -Message "Selected release: $selectedReleaseTag (asset: $assetName)"

        $step++; Write-Step $step "Download release asset"
        $zip = Join-Path $tmp.FullName 'overlay.zip'
        $assetStatusHints = @{
            401 = @{ Category = 'Unknown'; Hint = 'Authentication required for release asset' }
            403 = @{ Category = 'Unknown'; Hint = 'Access denied retrieving release asset' }
            404 = @{ Category = 'NotFound'; Hint = "Release asset $assetName not found" }
        }

        try {
            $downloadParams = @{
                Uri = $assetDownloadUrl
                OutFile = $zip
                Headers = @{
                    'Accept' = 'application/octet-stream'
                    'User-Agent' = 'al-build-tools-installer'
                }
                MaximumRedirection = 5
                ErrorAction = 'Stop'
            }
            if ($effectiveTimeoutSec -gt 0) {
                $downloadParams['TimeoutSec'] = $effectiveTimeoutSec
            }
            Invoke-WebRequest @downloadParams
        } catch {
            $failure = Resolve-DownloadFailureDetails -ErrorRecord $_ -DefaultHint 'Unable to download release asset' -StatusHints $assetStatusHints
            Write-Host "[install] download failure ref=`"$refForFailure`" url=`"$assetDownloadUrl`" category=$($failure.Category) hint=`"$($failure.Hint)`""
            Write-Error "Installation failed: Unable to download release asset. $($failure.Hint)"
        }

        $step++; Write-Step $step "Extract and locate '$Source'"
        $extract = Join-Path $tmp.FullName 'x'
        try {
            Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force -ErrorAction Stop
        } catch {
            Write-Host "[install] download failure ref=`"$refForFailure`" url=`"$assetDownloadUrl`" category=CorruptArchive hint=`"Failed to extract asset`""
            Write-Error "Installation failed: Failed to extract the downloaded archive. The file may be corrupted."
        }
        $top = Get-ChildItem -Path $extract -Directory | Select-Object -First 1
        if (-not $top) {
            Write-Host "[install] download failure ref=`"$refForFailure`" url=`"$assetDownloadUrl`" category=CorruptArchive hint=`"Asset archive appears empty`""
            Write-Error "Installation failed: Downloaded archive appears to be empty or corrupted."
        }
        $src = Join-Path $top.FullName $Source
        if (-not (Test-Path $src -PathType Container)) {
            $cand = Get-ChildItem -Path $extract -Recurse -Directory -Filter $Source | Select-Object -First 1
            if ($cand) {
                $src = $cand.FullName
            } else {
                Write-Host "[install] download failure ref=`"$refForFailure`" url=`"$assetDownloadUrl`" category=NotFound hint=`"Source folder '$Source' not found in asset`""
                Write-Error "Installation failed: Source folder '$Source' not found in the downloaded archive."
            }
        }

        if (-not (Get-ChildItem -Path $src -File -ErrorAction SilentlyContinue)) {
            Write-Host "[install] download failure ref=`"$refForFailure`" url=`"$assetDownloadUrl`" category=CorruptArchive hint=`"Source directory contains no files`""
            Write-Error "Installation failed: Source directory contains no files to install."
        }

        Write-BuildMessage -Type Success -Message "Source directory: $src"

        $step++; Write-Step $step "Copy files into destination"

        # FR-007: Verify all source files remain within destination boundary
        $overlayFiles = Get-ChildItem -Path $src -Recurse -File
        foreach ($file in $overlayFiles) {
            $relativePath = $file.FullName.Substring($src.Length).TrimStart('\', '/')
            $targetPath = Join-Path $destFull $relativePath
            $resolvedTarget = [System.IO.Path]::GetFullPath($targetPath)
            if (-not $resolvedTarget.StartsWith($destFull, [System.StringComparison]::OrdinalIgnoreCase)) {
                Write-Host "[install] guard RestrictedWrites"
                Write-Error "Installation failed: Security violation - attempt to write outside the destination directory."
            }
        }

        $fileCount = (Get-ChildItem -Path $src -Recurse -File | Measure-Object).Count
        $dirCount  = (Get-ChildItem -Path $src -Recurse -Directory | Measure-Object).Count + 1
        try {
            Copy-Item -Path (Join-Path $src '*') -Destination $destFull -Recurse -Force -ErrorAction Stop
        } catch [System.UnauthorizedAccessException], [System.IO.IOException] {
            Write-Host "[install] guard PermissionDenied"
            Write-Error "Installation failed: Permission denied. Please check that you have write permissions to the destination directory."
        }
        Write-BuildMessage -Type Success -Message "Copied $fileCount files across $dirCount directories"

        $endTime = Get-Date
        $durationSeconds = ($endTime - $startTime).TotalSeconds
        Write-Host "[install] success ref=`"$selectedReleaseTag`" overlay=`"$Source`" asset=`"$assetName`" duration=$($durationSeconds.ToString('F2', [System.Globalization.CultureInfo]::InvariantCulture))"
        Write-BuildMessage -Type Success -Message "Completed: $Source from $Url@$selectedReleaseTag into $destFull"

        # Offer to run provision task
        $step++; Write-Step $step "Optional: Run environment provisioning"

        # Detect non-interactive mode
        $isInteractive = $true
        try {
            if ($null -eq $Host.UI.RawUI -or $Host.Name -eq 'ServerRemoteHost') {
                $isInteractive = $false
            }
        } catch {
            $isInteractive = $false
        }

        if ($isInteractive) {
            Write-Host ""
            Write-Host "NEXT STEP: Environment Provisioning" -ForegroundColor Yellow
            Write-Host "The 'provision' task will:" -ForegroundColor Cyan
            Write-Host "  - Download and install the AL compiler as a .NET tool" -ForegroundColor White
            Write-Host "  - Download Business Central symbol packages based on your app.json" -ForegroundColor White
            Write-Host "  - Cache everything in your user profile for reuse across projects" -ForegroundColor White
            Write-Host ""
            Write-Host "This is a one-time setup per machine (or when dependencies change)." -ForegroundColor Cyan
            Write-Host ""
            Write-Host "Run provision now? (Y/n): " -NoNewline -ForegroundColor Yellow
            $response = Read-Host

            if ([string]::IsNullOrWhiteSpace($response) -or $response -ieq 'y' -or $response -ieq 'yes') {
                Write-Host "[install] provision accepted=true"
                Write-Host ""
                Write-BuildMessage -Type Info -Message "Running: Invoke-Build provision"
                Write-Host ""

                # Change to destination directory and run provision
                Push-Location $destFull
                try {
                    $provisionResult = & pwsh -NoProfile -Command "Invoke-Build provision"
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host ""
                        Write-BuildMessage -Type Success -Message "Provision completed successfully!"
                        Write-Host ""
                        Write-Host "You're all set! Try building your project:" -ForegroundColor Green
                        Write-Host "  Invoke-Build build" -ForegroundColor Cyan
                    } else {
                        Write-Warning "Provision task completed with errors (exit code: $LASTEXITCODE)"
                        Write-Host ""
                        Write-Host "You can retry manually by running:" -ForegroundColor Yellow
                        Write-Host "  Invoke-Build provision" -ForegroundColor Cyan
                    }
                } catch {
                    Write-Warning "Failed to run provision: $($_.Exception.Message)"
                    Write-Host ""
                    Write-Host "You can run it manually by executing:" -ForegroundColor Yellow
                    Write-Host "  Invoke-Build provision" -ForegroundColor Cyan
                } finally {
                    Pop-Location
                }
            } else {
                Write-Host "[install] provision accepted=false"
                Write-Host ""
                Write-BuildMessage -Type Info -Message "Skipping provision step"
                Write-Host ""
                Write-Host "To provision your environment later, run:" -ForegroundColor Cyan
                Write-Host "  Invoke-Build provision" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "Or provision and build in one command:" -ForegroundColor Cyan
                Write-Host "  Invoke-Build all" -ForegroundColor Yellow
            }
        } else {
            Write-Host "[install] provision skipped (non-interactive mode)"
            Write-Verbose "[install] Non-interactive mode - skipping provision prompt"
            Write-Host ""
            Write-BuildMessage -Type Info -Message "Installation complete. To provision your environment, run: Invoke-Build provision"
        }
    } finally {
        try { Remove-Item -Recurse -Force -LiteralPath $tmp.FullName -ErrorAction SilentlyContinue } catch { Write-Verbose "[install] cleanup failed: $($_.Exception.Message)" }
    }
}

# Auto-run only when executed as a script (not dot-sourced),
# and allow tests to disable via ALBT_NO_AUTORUN=1.
# - When dot-sourced, $MyInvocation.InvocationName is '.'
# - When executed via -File or &, InvocationName is the script name/path
if ($PSCommandPath -and ($MyInvocation.InvocationName -ne '.') -and -not $env:ALBT_NO_AUTORUN) {
    try {
        $installParams = @{
            Url = $Url
            Ref = $Ref
            Dest = $Dest
            Source = $Source
        }
        if ($PSBoundParameters.ContainsKey('HttpTimeoutSec')) {
            $installParams['HttpTimeoutSec'] = $HttpTimeoutSec
        }
        Install-AlBuildTools @installParams
    } catch {
        Write-Host "[install] error unhandled=$(ConvertTo-Json $_.Exception.Message -Compress)"
        Write-Error "Installation failed: An unexpected error occurred during installation. $($_.Exception.Message)"
    }
}
