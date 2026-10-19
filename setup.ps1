# One-command setup / update for Windows (Linux and macOS: setup.sh).
# 1. checks the prerequisites and prints the winget commands for what's missing,
# 2. creates the Python worker venv, builds the release backend and the
#    release app (wired to the launcher's port),
# 3. adds a "Music Player" Start Menu shortcut (skip it with -NoShortcut).
# Run from PowerShell in the repo folder:
#   powershell -ExecutionPolicy Bypass -File .\setup.ps1 [-NoShortcut] [-Check]
# Then start the app with launch.ps1 (or the "Music Player" shortcut).
param(
    [int]$Port = $(if ($env:GEONIX_PORT) { [int]$env:GEONIX_PORT } else { 7802 }),
    [switch]$NoShortcut,
    [switch]$Check
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

function Have($tool) { [bool](Get-Command $tool -ErrorAction SilentlyContinue) }
function Run($exe, [string[]]$arguments) {
    & $exe @arguments
    if ($LASTEXITCODE -ne 0) { throw "'$exe $($arguments -join ' ')' failed (exit $LASTEXITCODE)" }
}

# --- Prerequisites -------------------------------------------------------------
# "python3" on Windows is often the Microsoft Store stub, so prefer the py
# launcher, then python.
$Python = $null
foreach ($candidate in @(@('py', '-3'), @('python'))) {
    if (Have $candidate[0]) {
        try {
            & $candidate[0] @($candidate[1..9] + @('-c', 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)'))
            if ($LASTEXITCODE -eq 0) { $Python = $candidate; break }
        } catch { }
    }
}

$Missing = @()
if (-not (Have 'cargo')) { $Missing += , @('Rust', 'winget install -e --id Rustlang.Rustup   # then: rustup default stable') }
if (-not (Have 'flutter')) { $Missing += , @('Flutter', 'download the zip from https://docs.flutter.dev/get-started/install/windows/desktop, unpack it to C:\src\flutter and add C:\src\flutter\bin to your user PATH') }
if (-not $Python) { $Missing += , @('Python 3.11+', 'winget install -e --id Python.Python.3.12') }
if (-not (Have 'ffmpeg')) { $Missing += , @('ffmpeg', 'winget install -e --id Gyan.FFmpeg') }
if (-not (Have 'git')) { $Missing += , @('Git', 'winget install -e --id Git.Git') }
$VsWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$HasVc = $false
if (Test-Path $VsWhere) {
    $HasVc = [bool](& $VsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath)
}
if (-not $HasVc) {
    $Missing += , @('Visual Studio C++ build tools', 'winget install -e --id Microsoft.VisualStudio.2022.BuildTools --override "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"')
}

if ($Missing.Count -gt 0) {
    Write-Host 'Missing prerequisites. Install them with:' -ForegroundColor Yellow
    foreach ($m in $Missing) { Write-Host ("  {0}: {1}" -f $m[0], $m[1]) }
    Write-Host ''
    Write-Host 'Then close and reopen PowerShell (so PATH updates) and run setup.ps1 again.'
    Write-Host 'Details: README.md, "Getting started" > Windows.'
    exit 1
}

$DevMode = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' `
    -Name AllowDevelopmentWithoutDevLicense -ErrorAction SilentlyContinue
if (-not $DevMode -or $DevMode.AllowDevelopmentWithoutDevLicense -ne 1) {
    Write-Host 'Warning: Developer Mode seems to be off; Flutter plugins need it (symlinks).' -ForegroundColor Yellow
    Write-Host '  Turn it on with: start ms-settings:developers'
}
Write-Host "==> Prerequisites OK (python: $($Python -join ' '))"
if ($Check) { exit 0 }

# --- Build -------------------------------------------------------------------
Write-Host '==> Python worker (worker\.venv)'
$VenvPy = Join-Path $Root 'worker\.venv\Scripts\python.exe'
if (-not (Test-Path $VenvPy)) {
    Run $Python[0] @($Python[1..9] + @('-m', 'venv', (Join-Path $Root 'worker\.venv')))
}
Run $VenvPy @('-m', 'pip', 'install', '-q', '--upgrade', 'pip')
Run $VenvPy @('-m', 'pip', 'install', '-q', '--upgrade', '-r', (Join-Path $Root 'worker\requirements.txt'))

Write-Host '==> Rust backend (cargo build --release)'
Push-Location (Join-Path $Root 'backend')
try { Run 'cargo' @('build', '--release') } finally { Pop-Location }

Write-Host "==> Flutter app (port $Port)"
Push-Location (Join-Path $Root 'app')
try {
    Run 'flutter' @('pub', 'get')
    Run 'flutter' @('build', 'windows', '--release', "--dart-define=GEONIX_API=http://127.0.0.1:$Port")
} finally { Pop-Location }

# --- Start Menu shortcut -----------------------------------------------------
if (-not $NoShortcut) {
    $Programs = [Environment]::GetFolderPath('Programs')
    $Link = Join-Path $Programs 'Music Player.lnk'
    $Shell = New-Object -ComObject WScript.Shell
    $Shortcut = $Shell.CreateShortcut($Link)
    $Shortcut.TargetPath = Join-Path $PSHOME 'powershell.exe'
    $Shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $Root 'launch.ps1')`""
    $Shortcut.WorkingDirectory = $Root
    $Shortcut.IconLocation = (Join-Path $Root 'app\build\windows\x64\runner\Release\geonix_music_player.exe') + ',0'
    $Shortcut.Save()
    Write-Host "Start Menu shortcut: $Link"
}

Write-Host ''
Write-Host 'Done. Start it with .\launch.ps1 or the "Music Player" Start Menu shortcut:'
Write-Host '  powershell -ExecutionPolicy Bypass -File .\launch.ps1'
