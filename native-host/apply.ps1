# Restart worker, started detached by host.ps1:
# close Opera GX, set hardware acceleration in Local State, start Opera GX again.
param(
    [Parameter(Mandatory = $true)][ValidateSet('enable', 'disable')][string]$Mode,
    [Parameter(Mandatory = $true)][string]$InstallDir,
    [Parameter(Mandatory = $true)][string]$LocalState
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'common.ps1')

$enabled = $Mode -eq 'enable'
$launcher = Get-GxLauncher $InstallDir

function Wait-GxExit([int]$Seconds) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        if (-not (Get-GxProcesses $InstallDir)) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return -not (Get-GxProcesses $InstallDir)
}

# Only one restart at a time, however many requests arrive.
$mutex = New-Object System.Threading.Mutex($false, 'Local\accelplugin-apply')
if (-not $mutex.WaitOne(0)) {
    Write-AccelLog "worker: another restart is already running; mode=$Mode ignored."
    exit 0
}

try {
    Write-AccelLog "worker: mode=$Mode installDir='$InstallDir' localState='$LocalState'"
    # Give the host's reply time to reach the extension before Opera goes away.
    Start-Sleep -Milliseconds 1500

    # taskkill without /F asks the windows to close, like clicking X, so Opera saves its session.
    foreach ($p in Get-GxBrowserProcesses $InstallDir) {
        & taskkill.exe /PID $p.ProcessId 2>&1 | Out-Null
    }
    if (-not (Wait-GxExit 30)) {
        Write-AccelLog 'worker: Opera GX did not close within 30 s; forcing it.'
        foreach ($p in Get-GxProcesses $InstallDir) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
        if (-not (Wait-GxExit 10)) { throw 'Opera GX is still running; not touching Local State.' }
    }
    Start-Sleep -Milliseconds 500

    Set-HwAccelInFile $LocalState $enabled
    Write-AccelLog "worker: Local State updated, hardware acceleration enabled=$enabled"
} catch {
    Write-AccelLog "worker error: $($_.Exception.Message)"
} finally {
    # Always bring Opera GX back, even if the edit failed.
    if ($launcher -and -not (Get-GxBrowserProcesses $InstallDir)) {
        Start-Process -FilePath $launcher -ArgumentList '--restore-last-session' -WorkingDirectory (Split-Path -Parent $launcher)
        Write-AccelLog "worker: relaunched '$launcher'"
    }
    $mutex.ReleaseMutex()
}
