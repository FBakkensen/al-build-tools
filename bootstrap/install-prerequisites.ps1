# Allow execution under Windows PowerShell 5.1; script performs its own PS 7+ installation logic when needed.
[CmdletBinding()]
param(
    [string]$Dest = '.',
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArguments
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Handle $IsWindows for PowerShell 5.1 compatibility (added in PS 6.0)
if (-not (Get-Variable -Name 'IsWindows' -Scope Global -ErrorAction SilentlyContinue)) {
    $script:IsWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
}

if (-not $IsWindows) {
    Write-Error "Prerequisites installer is designed for Windows. For Linux, prerequisites should be installed via package manager."
}

# Reject unsupported parameters (usage guard)
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
    Write-Host "Usage: install-prerequisites.ps1 [-Dest <path>]"
    Write-Error "Installation failed: Unknown parameter '$argName'. Use: install-prerequisites.ps1 [-Dest <path>]"
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
        'Success' { Write-Host "[+] " -NoNewline -ForegroundColor Green; Write-Host $Message }
        'Warning' { Write-Host "[!] " -NoNewline -ForegroundColor Yellow; Write-Host $Message }
        'Error'   { Write-Host "[X] " -NoNewline -ForegroundColor Red; Write-Host $Message }
        'Step'    { Write-Host "[>] " -NoNewline -ForegroundColor Magenta; Write-Host $Message }
        'Detail'  { Write-Host "    - " -NoNewline -ForegroundColor Gray; Write-Host $Message -ForegroundColor Gray }
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
    [Console]::Out.Flush()
    Write-BuildMessage -Type Info -Message "Installing Chocolatey..."
    Write-Host "[install] Downloading Chocolatey install script (this may take a minute)..."
    [Console]::Out.Flush()

    $installScript = 'https://community.chocolatey.org/install.ps1'

    # Use official Chocolatey installation pattern (PowerShell version)
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

    # Set environment variable to install Chocolatey v1.x which doesn't require .NET 4.8
    # Windows Server Core 2022 containers have .NET 4.8, but installation may hang
    # Use v1.4.0 as last stable v1.x release
    if (-not $env:chocolateyVersion) {
        $env:chocolateyVersion = '1.4.0'
        Write-Host "[install] Using Chocolatey version $env:chocolateyVersion (v1.x compatible with .NET 4+)"
    }

    try {
        Write-Host "[install] Downloading from $installScript..."
        [Console]::Out.Flush()
        $wc = New-Object System.Net.WebClient
        $wc.Headers['User-Agent'] = 'al-build-tools-installer'
        $uri = [System.Uri]$installScript
        $req = [System.Net.HttpWebRequest]::Create($uri)
        $req.Method = 'GET'
        $req.UserAgent = 'al-build-tools-installer'
        $req.Timeout = 30000
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $response = $req.GetResponse()
        $stream = $response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $contentBuilder = New-Object System.Text.StringBuilder
        $lastSec = -1
        while (-not $reader.EndOfStream) {
            $chunk = $reader.ReadLine()
            [void]$contentBuilder.AppendLine($chunk)
            $sec = [int]$sw.Elapsed.TotalSeconds
            if ($sec -ne $lastSec) {
                $lastSec = $sec
                $bytes = $response.ContentLength
                Write-Host "[install] heartbeat phase=choco-download seconds=$sec bytes_expected=$bytes"
                [Console]::Out.Flush()
            }
        }
        $chocoInstallScript = $contentBuilder.ToString()
        Write-Host "[install] Download complete (elapsed=$($sw.Elapsed.TotalSeconds.ToString('F2'))) executing installation script..."
        [Console]::Out.Flush()
        Invoke-Expression $chocoInstallScript
        Write-Host "[install] Chocolatey installation completed"
        [Console]::Out.Flush()
        Write-Host "[install] prerequisite tool=`"choco`" status=`"installed`""
        [Console]::Out.Flush()
    } catch {
        throw "Chocolatey installation failed: $($_.Exception.Message)"
    } finally {
        # Clean up environment variable
        if ($env:chocolateyVersion -eq '1.4.0') {
            Remove-Item Env:\chocolateyVersion -ErrorAction SilentlyContinue
        }
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
        Write-Host "[install] choco feature enable allowGlobalConfirmation (streaming)"
        & $chocoPath feature enable -n=allowGlobalConfirmation 2>&1 | ForEach-Object {
            Write-Host "[choco] $_"
        }
        if ($LASTEXITCODE -ne 0) {
            Write-Verbose "[install] Failed to enable allowGlobalConfirmation (exit $LASTEXITCODE)"
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
    Write-Host "[install] choco exec args='$(($chocoArgs -join ' '))'"
    & $chocoPath @chocoArgs 2>&1 | ForEach-Object { Write-Host "[choco] $_" }
    if ($LASTEXITCODE -ne 0) {
        throw "Chocolatey command '$($Arguments -join ' ')'' exited with code $LASTEXITCODE"
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

    # Refresh PATH after installation
    $machinePath = [Environment]::GetEnvironmentVariable('PATH', [EnvironmentVariableTarget]::Machine)
    $userPath = [Environment]::GetEnvironmentVariable('PATH', [EnvironmentVariableTarget]::User)
    $env:PATH = "$machinePath;$userPath"

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

function Ensure-GitConfig {
    Write-Host "[install] prerequisite tool=`"git-config`" status=`"check`""

    # Check for existing global git config
    $userName = $null
    $userEmail = $null

    try {
        $userName = & git config --global --get user.name 2>$null
        $userEmail = & git config --global --get user.email 2>$null
    } catch {
        Write-Verbose "[install] Failed to check git config: $($_.Exception.Message)"
    }

    $configExists = (-not [string]::IsNullOrWhiteSpace($userName)) -and (-not [string]::IsNullOrWhiteSpace($userEmail))

    if ($configExists) {
        Write-Host "[install] prerequisite tool=`"git-config`" status=`"present`" user_name=`"$userName`" user_email=`"$userEmail`""
        Write-BuildMessage -Type Success -Message "Git is configured globally: $userName <$userEmail>"
        return $true
    }

    # Git config is missing - set it up
    if ($script:AutoInstallPrereqs) {
        Write-BuildMessage -Type Info -Message "Configuring git globally with CI credentials..."
        try {
            & git config --global user.email "ci@albt.test" 2>&1 | Out-Null
            & git config --global user.name "AL Build Tools CI" 2>&1 | Out-Null
            Write-Host "[install] prerequisite tool=`"git-config`" status=`"configured`" user_name=`"AL Build Tools CI`" user_email=`"ci@albt.test`""
            Write-BuildMessage -Type Success -Message "Git configured globally: AL Build Tools CI <ci@albt.test>"
        } catch {
            Write-Host "[install] prerequisite tool=`"git-config`" status=`"failed`""
            Write-Error "Failed to configure git: $($_.Exception.Message)"
        }
    } else {
        $shouldConfig = Confirm-Installation -ToolName "Git configuration" -Purpose "Committing changes to the repository"
        if ($shouldConfig) {
            Write-BuildMessage -Type Info -Message "Configuring git globally..."
            try {
                $email = Read-Host "Enter git user email"
                $name = Read-Host "Enter git user name"
                if ([string]::IsNullOrWhiteSpace($email)) { $email = "user@example.com" }
                if ([string]::IsNullOrWhiteSpace($name)) { $name = "User" }
                & git config --global user.email "$email" 2>&1 | Out-Null
                & git config --global user.name "$name" 2>&1 | Out-Null
                Write-Host "[install] prerequisite tool=`"git-config`" status=`"configured`" user_name=`"$name`" user_email=`"$email`""
                Write-BuildMessage -Type Success -Message "Git configured globally: $name <$email>"
            } catch {
                Write-Host "[install] prerequisite tool=`"git-config`" status=`"failed`""
                Write-Error "Failed to configure git: $($_.Exception.Message)"
            }
        } else {
            Write-Host "[install] guard MissingPrerequisite tool=`"git-config`" declined=true"
            Write-Error "Installation failed: Git configuration is required for repository operations."
        }
    }

    return $true
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
    Write-BuildMessage -Type Info -Message "Installing PowerShell 7..."

    try {
        # Download PowerShell 7 MSI installer
        $pwshVersion = '7.4.6'  # Use stable version
        $msiUrl = "https://github.com/PowerShell/PowerShell/releases/download/v$pwshVersion/PowerShell-$pwshVersion-win-x64.msi"
        $msiPath = Join-Path $env:TEMP "PowerShell-$pwshVersion-win-x64.msi"

        Write-BuildMessage -Type Info -Message "Downloading PowerShell $pwshVersion MSI..."
        Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath -UseBasicParsing -ErrorAction Stop

        Write-BuildMessage -Type Info -Message "Installing PowerShell $pwshVersion..."
        # Install silently with minimal options for container compatibility
        $msiArgs = "/i `"$msiPath`" /quiet /norestart ADD_PATH=1"
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru -NoNewWindow

        if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
            Write-Host "[install] prerequisite tool=`"pwsh`" status=`"installed`" relaunch_required=true"
            Write-BuildMessage -Type Success -Message "PowerShell 7 installed successfully"

            # Clean up installer
            try {
                Remove-Item $msiPath -Force -ErrorAction SilentlyContinue
            } catch {
                Write-Verbose "Failed to remove installer: $_"
            }

            Write-Host ""
            Write-Host "IMPORTANT: PowerShell 7 has been installed." -ForegroundColor Yellow
            Write-Host "Please close this window and rerun this script in PowerShell 7." -ForegroundColor Yellow
            Write-Host "You can start PowerShell 7 by running: pwsh" -ForegroundColor Cyan
            return $true
        } else {
            Write-Warning "PowerShell installation returned exit code: $($process.ExitCode)"
            return $false
        }
    } catch {
        Write-Warning "Failed to install PowerShell: $($_.Exception.Message)"
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
        # Ensure NuGet provider is installed (required for PowerShell 5.1)
        $nugetProvider = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
        if (-not $nugetProvider) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
        }

        # Ensure PSGallery is trusted
        $psGallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
        if ($null -ne $psGallery -and $psGallery.InstallationPolicy -ne 'Trusted') {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -WarningAction SilentlyContinue
        }

        Install-Module -Name InvokeBuild -Scope CurrentUser -Force -Repository PSGallery -SkipPublisherCheck -AllowClobber -ErrorAction Stop -Confirm:$false -WarningAction SilentlyContinue

        Write-Host "[install] prerequisite tool=`"InvokeBuild`" status=`"installed`""
        Write-BuildMessage -Type Success -Message "InvokeBuild module installed successfully"
        return $true
    } catch {
        Write-Warning "Failed to install InvokeBuild module: $($_.Exception.Message)"
        return $false
    }
}

function Install-Prerequisites {
    [CmdletBinding()]
    param(
        [string]$Dest = '.'
    )

    Write-BuildHeader "AL Build Tools - Prerequisites Installation"

    try {
        $destFull = (Resolve-Path -Path $Dest -ErrorAction Stop).Path
    } catch {
        # Create the destination if it does not exist, then resolve the actual path
        $created = New-Item -ItemType Directory -Force -Path $Dest
        $destFull = (Resolve-Path -Path $created.FullName).Path
    }

    Write-BuildMessage -Type Info -Message "Installing prerequisites for: $destFull"

    $result = @{
        'Chocolatey' = $null
        'Git' = $null
        'GitConfig' = $null
        'DotNetSDK' = $null
        'PowerShell7' = $null
        'InvokeBuild' = $null
    }

    # Step 1: Ensure Chocolatey
    Write-BuildMessage -Type Step -Message "Checking Chocolatey..."
    Write-Host "[install] prerequisite tool=`"choco`" status=`"check`""
    $chocoPath = Ensure-Chocolatey
    if ($chocoPath) {
        Write-BuildMessage -Type Success -Message "Chocolatey available at $chocoPath"
        $result['Chocolatey'] = 'present'
    }

    # Step 2: Ensure Git
    Write-BuildMessage -Type Step -Message "Checking Git..."
    Write-Host "[install] prerequisite tool=`"git`" status=`"check`""
    $gitPresent = Ensure-Git
    if ($gitPresent) {
        $result['Git'] = 'present'
    }

    # Step 3: Ensure Git Config
    Write-BuildMessage -Type Step -Message "Checking Git configuration..."
    Write-Host "[install] prerequisite tool=`"git-config`" status=`"check`""
    $gitConfigPresent = Ensure-GitConfig
    if ($gitConfigPresent) {
        $result['GitConfig'] = 'present'
    }

    # Step 4: Check .NET SDK
    Write-BuildMessage -Type Step -Message "Checking .NET SDK..."
    Write-Host "[install] prerequisite tool=`"dotnet`" status=`"check`""
    $hasDotNet = Test-DotNetSdk
    if ($hasDotNet) {
        $dotnetVersion = & dotnet --version 2>&1
        Write-Host "[install] prerequisite tool=`"dotnet`" status=`"present`" version=$dotnetVersion"
        Write-BuildMessage -Type Success -Message ".NET SDK is installed (version $dotnetVersion)"
        $result['DotNetSDK'] = 'present'
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
            $result['DotNetSDK'] = 'installed'
        } else{
            Write-Host "[install] guard MissingPrerequisite tool=`"dotnet`" declined=true"
            Write-Error "Installation failed: .NET SDK is required. Install from https://dotnet.microsoft.com/download"
        }
    }

    # Step 5: Check PowerShell version BEFORE InvokeBuild (InvokeBuild requires PS 7+)
    # First check if PowerShell 7 is already installed on the system
    $pwshExecutable = $null
    $pwshPath = 'C:\Program Files\PowerShell\7\pwsh.exe'
    $pwsh7Installed = Test-Path $pwshPath

    if ($pwsh7Installed) {
        # PowerShell 7 is already installed - get its version
        try {
            $pwsh7VersionOutput = & $pwshPath -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>&1
            $pwsh7Version = [System.Version]$pwsh7VersionOutput
            Write-Host "[install] prerequisite tool=`"pwsh`" status=`"check`" version=$pwsh7Version"

            if ($pwsh7Version -ge [System.Version]'7.2') {
                Write-Host "[install] prerequisite tool=`"pwsh`" status=`"present`" version=$pwsh7Version"
                Write-BuildMessage -Type Success -Message "PowerShell 7 is installed (version $pwsh7Version)"
                $pwshExecutable = $pwshPath
                $result['PowerShell7'] = 'present'
            } else {
                Write-Host "[install] prerequisite tool=`"pwsh`" status=`"insufficient`" installed_version=$pwsh7Version required=7.2"
                Write-Warning "PowerShell 7 is installed but version $pwsh7Version is below required 7.2"
                # Fall through to check current session and potentially install
            }
        } catch {
            Write-Verbose "[install] Failed to query PowerShell 7 version: $_"
            # Fall through to check current session
        }
    }

    # If PowerShell 7 is not already installed or version check failed, check current session
    if (-not $pwshExecutable) {
        $psVersion = if ($env:ALBT_TEST_FORCE_PSVERSION) {
            [System.Version]$env:ALBT_TEST_FORCE_PSVERSION
        } else {
            $PSVersionTable.PSVersion
        }

        Write-Host "[install] prerequisite tool=`"pwsh`" status=`"check`" version=$psVersion"

        $needsPowerShell7 = $psVersion -lt [System.Version]'7.2'

        if ($needsPowerShell7) {
            Write-Host "[install] prerequisite tool=`"pwsh`" status=`"insufficient`" required=7.2"

            $shouldInstall = Confirm-Installation -ToolName "PowerShell 7.2+" -Purpose "AL Build Tools installation and build operations"

            if ($shouldInstall) {
                $installed = Install-PowerShell
                if ($installed) {
                    # PowerShell 7 was installed - check if we can use it
                    if (Test-Path $pwshPath) {
                        $pwshExecutable = $pwshPath
                        Write-BuildMessage -Type Success -Message "PowerShell 7 installed successfully. Continuing with remaining tasks..."
                        $result['PowerShell7'] = 'installed'
                    } else {
                        Write-Host "[install] guard PowerShellVersionUnsupported version=$psVersion declined=false install_failed=true path_not_found=true"
                        Write-Error "Installation failed: PowerShell 7 installed but not found at expected path: $pwshPath"
                    }
                } else {
                    Write-Host "[install] guard PowerShellVersionUnsupported version=$psVersion declined=false install_failed=true"
                    Write-Error "Installation failed: Could not install PowerShell 7. Please install manually from https://aka.ms/powershell"
                }
            } else {
                Write-Host "[install] guard PowerShellVersionUnsupported version=$psVersion declined=true"
                Write-Error "Installation failed: PowerShell 7.2 or later is required. Current version: $psVersion. Install from https://aka.ms/powershell"
            }
        } else {
            $result['PowerShell7'] = 'present'
        }
    }

    # Step 6: Check InvokeBuild module (only after PowerShell 7+ is confirmed or installed)
    Write-BuildMessage -Type Step -Message "Checking InvokeBuild module..."
    Write-Host "[install] prerequisite tool=`"InvokeBuild`" status=`"check`""

    # If we just installed PS7, check for InvokeBuild using pwsh.exe
    $hasInvokeBuild = $false
    if ($pwshExecutable) {
        Write-Verbose "[install] Checking for InvokeBuild in PowerShell 7..."
        try {
            $checkScript = "Get-Module -ListAvailable -Name InvokeBuild -ErrorAction SilentlyContinue | Select-Object -First 1"
            $result_check = & $pwshExecutable -NoProfile -Command $checkScript 2>&1
            if ($result_check) {
                $hasInvokeBuild = $true
                Write-Host "[install] prerequisite tool=`"InvokeBuild`" status=`"present`" context=pwsh7"
            }
        } catch {
            Write-Verbose "[install] InvokeBuild check in PS7 failed: $_"
        }
    } else {
        $hasInvokeBuild = Test-InvokeBuildModule
    }

    if ($hasInvokeBuild) {
        $ibModule = Get-Module -ListAvailable -Name InvokeBuild -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($ibModule) {
            Write-Host "[install] prerequisite tool=`"InvokeBuild`" status=`"present`" version=$($ibModule.Version)"
            Write-BuildMessage -Type Success -Message "InvokeBuild module is installed (version $($ibModule.Version))"
        } else {
            Write-BuildMessage -Type Success -Message "InvokeBuild module is installed"
        }
        $result['InvokeBuild'] = 'present'
    } else {
        Write-Host "[install] prerequisite tool=`"InvokeBuild`" status=`"missing`""

        $shouldInstall = Confirm-Installation -ToolName "InvokeBuild module" -Purpose "Running build tasks and orchestrating the build process"

        if ($shouldInstall) {
            # If we have PS7 available, install InvokeBuild using pwsh
            if ($pwshExecutable) {
                Write-Host "[install] prerequisite tool=`"InvokeBuild`" status=`"installing`" context=pwsh7"
                Write-BuildMessage -Type Info -Message "Installing InvokeBuild module in PowerShell 7..."

                $installScript = @"
`$ErrorActionPreference = 'Stop'
try {
    # Ensure NuGet provider
    `$nuget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
    if (-not `$nuget) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:`$false | Out-Null
    }

    # Trust PSGallery
    `$gallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
    if (`$gallery -and `$gallery.InstallationPolicy -ne 'Trusted') {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    }

    # Install InvokeBuild
    Install-Module -Name InvokeBuild -Scope CurrentUser -Force -Repository PSGallery -SkipPublisherCheck -AllowClobber -Confirm:`$false
    exit 0
} catch {
    Write-Error `$_.Exception.Message
    exit 1
}
"@
                try {
                    & $pwshExecutable -NoProfile -Command $installScript
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "[install] prerequisite tool=`"InvokeBuild`" status=`"installed`" context=pwsh7"
                        Write-BuildMessage -Type Success -Message "InvokeBuild module installed successfully in PowerShell 7"
                        $result['InvokeBuild'] = 'installed'
                    } else {
                        Write-Host "[install] guard MissingPrerequisite tool=`"InvokeBuild`" declined=false install_failed=true context=pwsh7"
                        Write-Error "Installation failed: Could not install InvokeBuild module in PowerShell 7. Please install manually with: pwsh -Command 'Install-Module InvokeBuild -Scope CurrentUser'"
                    }
                } catch {
                    Write-Host "[install] guard MissingPrerequisite tool=`"InvokeBuild`" declined=false install_failed=true context=pwsh7 error=`"$($_.Exception.Message)`""
                    Write-Error "Installation failed: Could not install InvokeBuild module. Error: $($_.Exception.Message)"
                }
            } else {
                # Install in current PowerShell session
                $installed = Install-InvokeBuildModule
                if (-not $installed) {
                    Write-Host "[install] guard MissingPrerequisite tool=`"InvokeBuild`" declined=false install_failed=true"
                    Write-Error "Installation failed: Could not install InvokeBuild module. Please install manually with: Install-Module InvokeBuild -Scope CurrentUser"
                }
                Write-BuildMessage -Type Success -Message "InvokeBuild module is now installed"
                $result['InvokeBuild'] = 'installed'
            }
        } else {
            Write-Host "[install] guard MissingPrerequisite tool=`"InvokeBuild`" declined=true"
            Write-Error "Installation failed: InvokeBuild module is required. Install with: Install-Module InvokeBuild -Scope CurrentUser"
        }
    }

    Write-BuildHeader "Prerequisites Installation Complete"
    Write-BuildMessage -Type Success -Message "All prerequisites are installed and ready"

    # Return result summary
    return $result
}

# Auto-run only when executed as a script (not dot-sourced),
# and allow tests to disable via ALBT_NO_AUTORUN=1.
# - When dot-sourced, $MyInvocation.InvocationName is '.'
# - When executed via -File or &, InvocationName is the script name/path
if ($PSCommandPath -and ($MyInvocation.InvocationName -ne '.') -and -not $env:ALBT_NO_AUTORUN) {
    try {
        Install-Prerequisites -Dest $Dest
    } catch {
        Write-Host "[install] error unhandled=$(ConvertTo-Json $_.Exception.Message -Compress)"
        Write-Error "Prerequisites installation failed: An unexpected error occurred. $($_.Exception.Message)"
    }
}
