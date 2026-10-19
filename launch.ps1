# Desktop launcher for Music Player on Windows. Uses the prebuilt release
# binaries (build them once with setup.ps1), its own port and data folders,
# and stops the backend when the window closes.
#   powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File .\launch.ps1
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

if (-not $env:GEONIX_PORT) { $env:GEONIX_PORT = '7802' }
if (-not $env:GEONIX_DATA_DIR) { $env:GEONIX_DATA_DIR = Join-Path $env:LOCALAPPDATA 'Geonix' }
if (-not $env:GEONIX_MUSIC_DIR) { $env:GEONIX_MUSIC_DIR = Join-Path $env:USERPROFILE 'Music\Geonix' }
$env:GEONIX_WORKER = Join-Path $Root 'worker\worker.py'
$VenvPy = Join-Path $Root 'worker\.venv\Scripts\python.exe'
if ((Test-Path $VenvPy) -and -not $env:GEONIX_PYTHON) { $env:GEONIX_PYTHON = $VenvPy }

$Api = "http://127.0.0.1:$($env:GEONIX_PORT)"
$BackendBin = Join-Path $Root 'backend\target\release\geonix-backend.exe'
$AppBin = Join-Path $Root 'app\build\windows\x64\runner\Release\geonix_music_player.exe'
New-Item -ItemType Directory -Force -Path $env:GEONIX_DATA_DIR, $env:GEONIX_MUSIC_DIR | Out-Null
$Log = Join-Path $env:GEONIX_DATA_DIR 'launch.log'
$BackendLog = Join-Path $env:GEONIX_DATA_DIR 'backend.log'
$BackendErr = Join-Path $env:GEONIX_DATA_DIR 'backend.err.log'

function Log($msg) { Add-Content -Path $Log -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg" }

function Fail($msg) {
    Log "ERROR: $msg"
    try {
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show("$msg`n`nSee $Log", 'Music Player failed to start', 'OK', 'Error') | Out-Null
    } catch { Write-Error $msg }
    exit 1
}

function Healthy {
    try {
        $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 1 -Uri "$Api/api/health"
        return $r.StatusCode -eq 200
    } catch { return $false }
}

Log '=== launch'

# YouTube changes often and old yt-dlp versions start failing (HTTP 403):
# update it in the background at most once a week. Takes effect next launch.
$Stamp = Join-Path $env:GEONIX_DATA_DIR '.yt-dlp-updated'
if ((Test-Path $VenvPy) -and -not ((Test-Path $Stamp) -and ((Get-Item $Stamp).LastWriteTime -gt (Get-Date).AddDays(-7)))) {
    $cmd = "& '$VenvPy' -m pip install -q --upgrade yt-dlp; if (`$LASTEXITCODE -eq 0) { Set-Content -Path '$Stamp' -Value (Get-Date) }"
    Start-Process -WindowStyle Hidden -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList '-NoProfile', '-Command', $cmd | Out-Null
}

if (-not (Test-Path $BackendBin)) { Fail 'Backend not built. Run setup.ps1 once.' }
if (-not (Test-Path $AppBin)) { Fail 'App not built. Run setup.ps1 once.' }

$Backend = $null
try {
    if (-not (Healthy)) {
        $Backend = Start-Process -FilePath $BackendBin -WorkingDirectory $Root -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput $BackendLog -RedirectStandardError $BackendErr
        $ok = $false
        for ($i = 0; $i -lt 100; $i++) {
            if (Healthy) { $ok = $true; break }
            if ($Backend.HasExited) { Fail "Backend exited during startup. See $BackendErr" }
            Start-Sleep -Milliseconds 100
        }
        if (-not $ok -and -not (Healthy)) { Fail "Backend did not answer on port $($env:GEONIX_PORT)." }
    }

    Start-Process -FilePath $AppBin -WorkingDirectory (Split-Path -Parent $AppBin) -Wait
    Log '=== app closed'
} finally {
    if ($Backend -and -not $Backend.HasExited) {
        # /T also ends the Python worker the backend started.
        try { & taskkill.exe /PID $Backend.Id /T /F | Out-Null } catch { }
    }
}
