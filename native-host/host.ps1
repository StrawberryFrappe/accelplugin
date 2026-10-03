# Native messaging host for the HW Accel Toggler extension.
# The browser starts this (through host.bat) for each message; it answers once and exits.
# Protocol: 4-byte little-endian length + UTF-8 JSON, on stdin/stdout.
# Nothing else may be written to stdout.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'common.ps1')

$stdin = [Console]::OpenStandardInput()
$stdout = [Console]::OpenStandardOutput()

function Read-Exact([int]$Count) {
    $buf = New-Object byte[] $Count
    $read = 0
    while ($read -lt $Count) {
        $n = $stdin.Read($buf, $read, $Count - $read)
        if ($n -le 0) { return $null }
        $read += $n
    }
    return ,$buf
}

function Read-NativeMessage {
    $len = Read-Exact 4
    if ($null -eq $len) { return $null }
    $size = [BitConverter]::ToInt32($len, 0)
    if ($size -le 0 -or $size -gt 1MB) { throw "Bad message length $size." }
    $body = Read-Exact $size
    if ($null -eq $body) { return $null }
    return [System.Text.Encoding]::UTF8.GetString($body) | ConvertFrom-Json
}

function Write-NativeMessage($Obj) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($Obj | ConvertTo-Json -Compress -Depth 5))
    $stdout.Write([BitConverter]::GetBytes([int32]$bytes.Length), 0, 4)
    $stdout.Write($bytes, 0, $bytes.Length)
    $stdout.Flush()
}

# Start a process outside of the browser's process tree so it survives the browser closing.
function Start-Detached([string]$CommandLine) {
    try {
        $startup = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ ShowWindow = [uint16]0 }
        $r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
            CommandLine = $CommandLine
            ProcessStartupInformation = $startup
        }
        if ($r.ReturnValue -eq 0) { return $r.ProcessId }
        Write-AccelLog "host: Win32_Process.Create returned $($r.ReturnValue); falling back to Start-Process"
    } catch {
        Write-AccelLog "host: Win32_Process.Create failed ($($_.Exception.Message)); falling back to Start-Process"
    }
    $exe, $argLine = $CommandLine -split ' ', 2
    $p = Start-Process -FilePath $exe.Trim('"') -ArgumentList $argLine -WindowStyle Hidden -PassThru
    return $p.Id
}

function Invoke-HostCommand($Msg) {
    $config = Get-AccelConfig
    switch ($Msg.cmd) {
        'getState' {
            $id = Resolve-CallingBrowser $config $Msg.browser
            $b = $config[$id]
            $s = Read-BrowserHwState $b.def $b.settings
            $reply = @{ ok = $true; browser = $id; browserName = $b.def.name; running = $s.running; pending = $s.pending; settings = $b.settings }
            if ($s.warning) { $reply.warning = $s.warning }
            return $reply
        }
        'apply' {
            if ($Msg.enabled -isnot [bool]) { throw "'enabled' must be true or false." }
            $id = Resolve-CallingBrowser $config $Msg.browser
            $b = $config[$id]
            $def = $b.def
            $state = Read-BrowserHwState $def $b.settings
            $launcher = Get-BrowserLauncher $def $b.installDir
            if (-not $launcher) { throw "Could not find the $($def.name) install folder. Re-run native-host\install.bat." }
            $mainPids = @(Get-BrowserMainProcesses $def $b.installDir | ForEach-Object { $_.ProcessId })
            if (-not $mainPids.Count) { throw "No running $($def.name) found under '$($b.installDir)'." }

            $info = @{
                ok = $true
                browser = $id
                browserName = $def.name
                installDir = $b.installDir
                launcher = $launcher
                settings = $b.settings
                browserPids = $mainPids
                running = $state.running
                pending = $state.pending
            }
            if ($state.warning) { $info.warning = $state.warning }
            if ($Msg.dryRun) { $info.dryRun = $true; return $info }

            $mode = if ($Msg.enabled) { 'enable' } else { 'disable' }
            $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $worker = Join-Path $PSScriptRoot 'apply.ps1'
            $cmd = "`"$powershell`" -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$worker`" -Browser $id -Mode $mode -InstallDir `"$($b.installDir)`" -SettingsPath `"$($b.settings)`""
            $info.workerPid = Start-Detached $cmd
            Write-AccelLog "host: started worker pid=$($info.workerPid) browser=$id mode=$mode"
            return $info
        }
        default { throw "Unknown command '$($Msg.cmd)'." }
    }
}

try {
    $msg = Read-NativeMessage
    if ($null -eq $msg) { exit 0 }
    $reply = Invoke-HostCommand $msg
} catch {
    Write-AccelLog "host error: $($_.Exception.Message)"
    $reply = @{ ok = $false; error = $_.Exception.Message }
}
Write-NativeMessage $reply
