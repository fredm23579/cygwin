#Requires -Version 5.1
<#
.SYNOPSIS
    One-shot Windows developer environment setup for Cygwin development.

.DESCRIPTION
    Installs and configures everything needed to build and develop Cygwin on a
    fresh Windows machine:

      - Cygwin (x86_64) with all required build packages
      - PowerShell 7+ (pwsh) via winget or direct download
      - Windows Terminal
      - Visual Studio Code with C/C++ and Bash extensions
      - Git for Windows
      - GitHub CLI (gh)
      - Optional: WSL 2 for side-by-side Linux comparison

    Safe to re-run: each step is idempotent (skips if already installed).

.PARAMETER CygwinRoot
    Where to install Cygwin. Default: C:\cygwin64

.PARAMETER CygwinMirror
    Cygwin package mirror URL. Default: https://mirrors.kernel.org/sourceware/cygwin/

.PARAMETER SkipVSCode
    Skip Visual Studio Code installation.

.PARAMETER SkipWSL
    Skip WSL 2 installation.

.PARAMETER InstallFromSource
    After installing Cygwin, check out this repo and attempt a build.

.PARAMETER CacheDir
    Directory for downloaded installers and Cygwin packages. Default: C:\cygwin-cache

.EXAMPLE
    # Basic install with all defaults
    .\scripts\windows\setup-windows.ps1

    # Install to custom root, skip VSCode
    .\scripts\windows\setup-windows.ps1 -CygwinRoot D:\tools\cygwin -SkipVSCode

    # Full setup including build from source
    .\scripts\windows\setup-windows.ps1 -InstallFromSource
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]  $CygwinRoot       = 'C:\cygwin64',
    [string]  $CygwinMirror     = 'https://mirrors.kernel.org/sourceware/cygwin/',
    [string]  $CacheDir         = 'C:\cygwin-cache',
    [switch]  $SkipVSCode,
    [switch]  $SkipWSL,
    [switch]  $InstallFromSource
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Helper functions ───────────────────────────────────────────────────────────

function Write-Step {
    param([string]$Message)
    Write-Host "`n▶ $Message" -ForegroundColor Cyan
}

function Write-OK {
    param([string]$Message)
    Write-Host "  ✓ $Message" -ForegroundColor Green
}

function Write-Skip {
    param([string]$Message)
    Write-Host "  ○ $Message (already installed — skipping)" -ForegroundColor DarkGray
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  ! $Message" -ForegroundColor Yellow
}

function Test-CommandExists {
    param([string]$Name)
    $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-WingetAvailable {
    Test-CommandExists 'winget'
}

# ── Elevation check ───────────────────────────────────────────────────────────

Write-Step "Checking elevation"
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    Write-Warn "Script is NOT running as Administrator."
    Write-Warn "Some installations (Cygwin, WSL) require elevation."
    Write-Warn "Re-run from an elevated PowerShell prompt for full setup."
    Write-Warn "Continuing with user-level installs only..."
}

# ── Create cache directory ─────────────────────────────────────────────────────

Write-Step "Preparing cache directory: $CacheDir"
New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null
Write-OK "Cache directory ready: $CacheDir"

# ── PowerShell 7+ ─────────────────────────────────────────────────────────────

Write-Step "PowerShell 7+ (pwsh)"
if (Test-CommandExists 'pwsh') {
    $pwshVer = (pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>$null)
    Write-Skip "pwsh $pwshVer"
} elseif (Test-WingetAvailable) {
    if ($PSCmdlet.ShouldProcess('PowerShell 7', 'Install via winget')) {
        winget install --id Microsoft.PowerShell --exact --silent --accept-source-agreements
        Write-OK "PowerShell 7 installed"
    }
} else {
    Write-Warn "winget not available. Download PowerShell 7 from:"
    Write-Warn "  https://github.com/PowerShell/PowerShell/releases"
}

# ── Windows Terminal ───────────────────────────────────────────────────────────

Write-Step "Windows Terminal"
$wtPath = "$env:LOCALAPPDATA\Microsoft\WindowsApps\wt.exe"
if (Test-Path $wtPath) {
    Write-Skip "Windows Terminal (already installed)"
} elseif (Test-WingetAvailable) {
    if ($PSCmdlet.ShouldProcess('Windows Terminal', 'Install via winget')) {
        winget install --id Microsoft.WindowsTerminal --exact --silent --accept-source-agreements
        Write-OK "Windows Terminal installed"
    }
} else {
    Write-Warn "Install Windows Terminal from the Microsoft Store or:"
    Write-Warn "  https://github.com/microsoft/terminal/releases"
}

# ── Git for Windows ────────────────────────────────────────────────────────────

Write-Step "Git for Windows"
$gitPath = 'C:\Program Files\Git\bin\git.exe'
if (Test-Path $gitPath) {
    $gitVer = & $gitPath --version 2>$null
    Write-Skip $gitVer
} elseif (Test-WingetAvailable) {
    if ($PSCmdlet.ShouldProcess('Git for Windows', 'Install via winget')) {
        winget install --id Git.Git --exact --silent --accept-source-agreements `
            --override '/VERYSILENT /NORESTART /COMPONENTS="icons,ext\reg\shellhere,assoc,assoc_sh" /o:PathOption=CmdTools /o:CRLFOption=CRLFCommitAsIs'
        Write-OK "Git for Windows installed"

        # Configure line endings for Cygwin compatibility
        & 'C:\Program Files\Git\bin\git.exe' config --global core.autocrlf input
        Write-OK "Set core.autocrlf=input (CRLF → LF on commit)"
    }
} else {
    Write-Warn "Download Git for Windows from https://gitforwindows.org/"
}

# ── GitHub CLI ────────────────────────────────────────────────────────────────

Write-Step "GitHub CLI (gh)"
if (Test-CommandExists 'gh') {
    $ghVer = & gh --version 2>$null | Select-Object -First 1
    Write-Skip $ghVer
} elseif (Test-WingetAvailable) {
    if ($PSCmdlet.ShouldProcess('GitHub CLI', 'Install via winget')) {
        winget install --id GitHub.cli --exact --silent --accept-source-agreements
        Write-OK "GitHub CLI installed"
    }
}

# ── Visual Studio Code ────────────────────────────────────────────────────────

Write-Step "Visual Studio Code"
if ($SkipVSCode) {
    Write-Warn "Skipping VSCode installation (-SkipVSCode specified)"
} else {
    $codePaths = @(
        "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd",
        'C:\Program Files\Microsoft VS Code\bin\code.cmd'
    )
    $codeInstalled = $codePaths | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($codeInstalled) {
        Write-Skip "VSCode (found at: $codeInstalled)"
    } elseif (Test-WingetAvailable) {
        if ($PSCmdlet.ShouldProcess('Visual Studio Code', 'Install via winget')) {
            winget install --id Microsoft.VisualStudioCode --exact --silent --accept-source-agreements `
                --override '/VERYSILENT /NORESTART /MERGETASKS=!runcode,addcontextmenufiles,addcontextmenufolders,associatewithfiles,addtopath'
            Write-OK "VSCode installed"

            # Reload PATH so 'code' is available
            $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' +
                        [System.Environment]::GetEnvironmentVariable('PATH', 'User')

            # Install recommended extensions for Cygwin development
            $extensions = @(
                'ms-vscode.cpptools',
                'ms-vscode.cpptools-extension-pack',
                'mads-hartmann.bash-ide-vscode',
                'timonwong.shellcheck',
                'redhat.vscode-xml',
                'editorconfig.editorconfig',
                'eamodio.gitlens',
                'github.copilot',
                'github.copilot-chat',
                'ms-vscode.makefile-tools'
            )
            foreach ($ext in $extensions) {
                Write-Host "    Installing extension: $ext" -ForegroundColor DarkGray
                & code --install-extension $ext --force 2>$null
            }
            Write-OK "VSCode extensions installed"
        }
    } else {
        Write-Warn "Download VSCode from https://code.visualstudio.com/"
    }
}

# ── Cygwin ────────────────────────────────────────────────────────────────────

Write-Step "Cygwin x86_64"
$cygwinBash = "$CygwinRoot\bin\bash.exe"

# The authoritative build-dependency package list (keep in sync with cygwin.yml)
$cygwinPackages = @(
    'autoconf', 'automake', 'make', 'patch', 'perl',
    'gcc-core', 'gcc-g++', 'cocom',
    'gettext-devel', 'libiconv-devel', 'libzstd-devel', 'zlib-devel',
    'mingw64-x86_64-gcc-g++', 'mingw64-x86_64-zlib',
    'python3', 'python3-lxml', 'python3-ply',
    'git', 'curl', 'wget', 'vim', 'bash-completion',
    'dblatex', 'docbook2X', 'docbook-xml45', 'docbook-xsl', 'xmlto',
    'texlive-collection-latexrecommended', 'texlive-collection-fontsrecommended',
    'texlive-collection-pictures',
    'dejagnu', 'busybox', 'cygutils-extra',
    'openssh', 'rsync', 'unzip', 'zip'
) -join ','

# Download setup.exe
$setupExe = "$CacheDir\setup-x86_64.exe"
if (-not (Test-Path $setupExe)) {
    Write-Host "  Downloading Cygwin setup.exe…" -ForegroundColor DarkGray
    $setupUrl = 'https://cygwin.com/setup-x86_64.exe'
    Invoke-WebRequest -Uri $setupUrl -OutFile $setupExe -UseBasicParsing
    Write-OK "Downloaded: $setupExe"
}

if (Test-Path $cygwinBash) {
    Write-Skip "Cygwin (already installed at $CygwinRoot)"
    Write-Host "  Updating packages…" -ForegroundColor DarkGray
} else {
    Write-Host "  Installing Cygwin to $CygwinRoot…" -ForegroundColor DarkGray
}

if ($PSCmdlet.ShouldProcess("Cygwin ($CygwinRoot)", 'Install / update')) {
    & $setupExe `
        --quiet-mode `
        --no-shortcuts `
        --no-startmenu `
        --download `
        --only-site `
        --root $CygwinRoot `
        --site $CygwinMirror `
        --local-package-dir $CacheDir `
        --packages $cygwinPackages

    if (Test-Path $cygwinBash) {
        Write-OK "Cygwin installed/updated at $CygwinRoot"
    } else {
        Write-Warn "Cygwin setup completed but bash.exe not found. Check $CygwinRoot"
    }
}

# ── Configure Windows Terminal Cygwin profile ─────────────────────────────────

Write-Step "Windows Terminal: adding Cygwin profile"
$wtSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
if (Test-Path $wtSettingsPath) {
    try {
        $settings = Get-Content $wtSettingsPath -Raw | ConvertFrom-Json

        # Check if Cygwin profile already exists
        $existingProfile = $settings.profiles.list | Where-Object { $_.name -eq 'Cygwin' }
        if ($existingProfile) {
            Write-Skip "Cygwin profile already in Windows Terminal"
        } else {
            $cygwinProfile = [PSCustomObject]@{
                name             = 'Cygwin'
                commandline      = "$CygwinRoot\bin\bash.exe --login -i"
                icon             = "$CygwinRoot\Cygwin.ico"
                startingDirectory= '%USERPROFILE%'
                cursorShape      = 'bar'
                antialiasingMode = 'cleartype'
                env              = @{
                    CHERE_INVOKING = '1'
                    CYGWIN         = 'winsymlinks:nativestrict'
                }
            }
            $settings.profiles.list += $cygwinProfile
            $settings | ConvertTo-Json -Depth 10 | Set-Content $wtSettingsPath -Encoding UTF8
            Write-OK "Cygwin profile added to Windows Terminal"
        }
    } catch {
        Write-Warn "Could not update Windows Terminal settings: $_"
    }
} else {
    Write-Warn "Windows Terminal settings not found. Install Windows Terminal first."
}

# ── WSL 2 (optional) ──────────────────────────────────────────────────────────

Write-Step "Windows Subsystem for Linux (WSL 2)"
if ($SkipWSL) {
    Write-Warn "Skipping WSL installation (-SkipWSL specified)"
} elseif (-not $isAdmin) {
    Write-Warn "WSL installation requires Administrator privileges. Skipping."
} else {
    $wslState = (wsl --status 2>$null) -join ' '
    if ($wslState -match 'Default Version: 2') {
        Write-Skip "WSL 2 (already installed)"
    } else {
        if ($PSCmdlet.ShouldProcess('WSL 2', 'Enable and install')) {
            wsl --install --no-distribution
            Write-OK "WSL 2 installed. Reboot may be required."
            Write-Warn "After reboot, install a distro: wsl --install -d Ubuntu"
        }
    }
}

# ── PATH additions ─────────────────────────────────────────────────────────────

Write-Step "Updating user PATH"
$cygwinBinPath = "$CygwinRoot\bin"
$userPath = [System.Environment]::GetEnvironmentVariable('PATH', 'User')

if ($userPath -notlike "*$cygwinBinPath*") {
    [System.Environment]::SetEnvironmentVariable(
        'PATH',
        "$userPath;$cygwinBinPath",
        'User'
    )
    Write-OK "Added Cygwin bin to user PATH: $cygwinBinPath"
} else {
    Write-Skip "Cygwin already in PATH"
}

# ── Final summary ──────────────────────────────────────────────────────────────

Write-Host "`n" + ('─' * 60) -ForegroundColor DarkGray
Write-Host "`n✅  Setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Open Windows Terminal and select the 'Cygwin' profile"
Write-Host "  2. Run: bash scripts/windows/wintools-detect.sh"
Write-Host "  3. Run: bash scripts/update-check.sh"
Write-Host "  4. Build: bash scripts/windows/vscode-integration.sh --init"
Write-Host ""
Write-Host "Documentation:" -ForegroundColor Cyan
Write-Host "  CLAUDE.md   — AI assistant context guide"
Write-Host "  README.md   — Project overview"
Write-Host ""

if ($InstallFromSource) {
    Write-Step "Building Cygwin from source"
    $bashExe = "$CygwinRoot\bin\bash.exe"
    if (Test-Path $bashExe) {
        & $bashExe --login -c @"
set -euo pipefail
cd '$($PWD.Path -replace '\\', '/')' 2>/dev/null || cd "\$HOME"
echo "Starting build..."
bash scripts/update-check.sh
mkdir -p build install
(cd winsup && ./autogen.sh)
(cd build && ../configure --target=x86_64-pc-cygwin --prefix=\$(realpath ../install) -v)
make -j\$(nproc) -C build
echo "Build complete!"
"@
    } else {
        Write-Warn "Cygwin bash not found. Cannot build from source."
    }
}
