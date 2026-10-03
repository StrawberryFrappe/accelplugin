# Restart worker, started detached by host.ps1:
# close the browser, set hardware acceleration in its settings file, start it again.
param(
    [Parameter(Mandatory = $true)][ValidateSet('operagx', 'chrome', 'brave', 'firefox')][string]$Browser,
    [Parameter(Mandatory = $true)][ValidateSet('enable', 'disable')][string]$Mode,
    [Parameter(Mandatory = $true)][string]$InstallDir,
    [Parameter(Mandatory = $true)][string]$SettingsPath
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'common.ps1')

$def = Get-BrowserDef $Browser
$enabled = $Mode -eq 'enable'
$launcher = Get-BrowserLauncher $def $InstallDir

# Wait for every process of the browser to exit. A browser that closed all its windows but
# keeps running in the background (Chrome's "Continue running background apps") is reported
# as not exiting after a few seconds, instead of waiting out the full timeout.
function Wait-BrowserExit([int]$Seconds) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    $windowlessSince = $null
    while ((Get-Date) -lt $deadline) {
        if (-not (Get-BrowserProcesses $def $InstallDir)) { return $true }
        $hasWindow = $false
        foreach ($p in Get-BrowserMainProcesses $def $InstallDir) {
            $gp = Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue
            if ($gp -and $gp.MainWindowHandle -ne [IntPtr]::Zero) { $hasWindow = $true }
        }
        if ($hasWindow) { $windowlessSince = $null }
        elseif (-not $windowlessSince) { $windowlessSince = Get-Date }
        elseif (((Get-Date) - $windowlessSince).TotalSeconds -ge 8) { return $false }
        Start-Sleep -Milliseconds 500
    }
    return -not (Get-BrowserProcesses $def $InstallDir)
}

# Only one restart at a time, however many requests arrive.
$mutex = New-Object System.Threading.Mutex($false, 'Local\accelplugin-apply')
if (-not $mutex.WaitOne(0)) {
    Write-AccelLog "worker: another restart is already running; $Browser mode=$Mode ignored."
    exit 0
}

try {
    Write-AccelLog "worker: browser=$Browser mode=$Mode installDir='$InstallDir' settings='$SettingsPath'"
    # Give the host's reply time to reach the extension before the browser goes away.
    Start-Sleep -Milliseconds 1500

    # taskkill without /F asks the windows to close, like clicking X, so the browser saves its session.
    foreach ($p in Get-BrowserMainProcesses $def $InstallDir) {
        & taskkill.exe /PID $p.ProcessId 2>&1 | Out-Null
    }
    if (-not (Wait-BrowserExit 30)) {
        Write-AccelLog "worker: $($def.name) did not exit; forcing it."
        foreach ($p in Get-BrowserProcesses $def $InstallDir) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
        if (-not (Wait-BrowserExit 10)) { throw "$($def.name) is still running; not touching its settings." }
    }
    Start-Sleep -Milliseconds 500

    Set-BrowserHwState $def $SettingsPath $enabled
    Write-AccelLog "worker: settings updated, hardware acceleration enabled=$enabled"
} catch {
    Write-AccelLog "worker error: $($_.Exception.Message)"
} finally {
    # Always bring the browser back, even if the edit failed.
    if ($launcher -and -not (Get-BrowserMainProcesses $def $InstallDir)) {
        $start = @{ FilePath = $launcher; WorkingDirectory = (Split-Path -Parent $launcher) }
        if ($def.relaunchArgs.Count) { $start.ArgumentList = $def.relaunchArgs }
        Start-Process @start
        Write-AccelLog "worker: relaunched '$launcher'"
    }
    $mutex.ReleaseMutex()
}
