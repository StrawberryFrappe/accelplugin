# Shared helpers for host.ps1, apply.ps1 and install.ps1. Dot-source this file.
# Must stay compatible with Windows PowerShell 5.1.

$script:AccelHostName = 'com.accelplugin.hwaccel'
$script:AccelLogDir = Join-Path $env:LOCALAPPDATA 'accelplugin'
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding $false

function Write-AccelLog([string]$Message) {
    try {
        if (-not (Test-Path $script:AccelLogDir)) { New-Item -ItemType Directory -Path $script:AccelLogDir -Force | Out-Null }
        $log = Join-Path $script:AccelLogDir 'apply.log'
        if ((Test-Path $log) -and (Get-Item $log).Length -gt 512KB) { Move-Item $log "$log.old" -Force }
        $line = '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f (Get-Date), $PID, $Message
        [System.IO.File]::AppendAllText($log, $line + [Environment]::NewLine, $script:Utf8NoBom)
    } catch { }
}

# ------------------------------------------------------------------ Opera GX location

function Get-DefaultLocalStatePath {
    Join-Path $env:APPDATA 'Opera Software\Opera GX Stable\Local State'
}

function Get-AccelConfig {
    $cfg = [ordered]@{ installDir = $null; localState = $null }
    $path = Join-Path $PSScriptRoot 'config.json'
    if (Test-Path $path) {
        $saved = [System.IO.File]::ReadAllText($path) | ConvertFrom-Json
        if ($saved.installDir) { $cfg.installDir = $saved.installDir }
        if ($saved.localState) { $cfg.localState = $saved.localState }
    }
    if (-not $cfg.localState) { $cfg.localState = Get-DefaultLocalStatePath }
    if (-not $cfg.installDir) { $cfg.installDir = Find-GxInstallDir }
    return $cfg
}

# Opera GX ships launcher.exe in the install folder and the real browser in a versioned subfolder.
function Find-GxInstallDir {
    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($p in Get-GxProcesses) {
        if ($p.ExecutablePath) {
            $dir = Split-Path -Parent $p.ExecutablePath
            $candidates.Add($dir)
            $candidates.Add((Split-Path -Parent $dir))
        }
    }
    foreach ($key in 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
                     'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
                     'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*') {
        Get-ItemProperty $key -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like 'Opera GX*' -and $_.InstallLocation } |
            ForEach-Object { $candidates.Add($_.InstallLocation.TrimEnd('\')) }
    }
    if ($env:LOCALAPPDATA) { $candidates.Add((Join-Path $env:LOCALAPPDATA 'Programs\Opera GX')) }
    if ($env:ProgramFiles) { $candidates.Add((Join-Path $env:ProgramFiles 'Opera GX')) }
    foreach ($dir in $candidates) {
        if ($dir -and (Test-Path (Join-Path $dir 'launcher.exe'))) { return $dir }
    }
    return $null
}

# All opera.exe processes belonging to Opera GX (never regular Opera).
function Get-GxProcesses([string]$InstallDir) {
    $all = @(Get-CimInstance Win32_Process -Filter "Name = 'opera.exe'" -ErrorAction SilentlyContinue)
    if ($InstallDir) {
        $prefix = $InstallDir.TrimEnd('\') + '\'
        return @($all | Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) })
    }
    return @($all | Where-Object { $_.ExecutablePath -like '*\Opera GX\*' })
}

# Browser (main) processes are the ones without a --type= switch.
function Get-GxBrowserProcesses([string]$InstallDir) {
    return @(Get-GxProcesses $InstallDir | Where-Object { $_.CommandLine -notmatch '--type=' })
}

function Get-GxLauncher([string]$InstallDir) {
    if (-not $InstallDir) { return $null }
    foreach ($name in 'launcher.exe', 'opera.exe') {
        $p = Join-Path $InstallDir $name
        if (Test-Path $p) { return $p }
    }
    return $null
}

# ------------------------------------------------------------------ Local State

# Chromium stores the setting in Local State as
#   "hardware_acceleration_mode":{"enabled":false}        (what applies on next start)
#   "hardware_acceleration_mode_previous":false           (what the running browser started with)
# Both default to true and are only written when they differ from the default.

function Get-HwAccelFromText([string]$Text) {
    $enabled = $true
    $previous = $true
    $m = [regex]::Match($Text, '"hardware_acceleration_mode"\s*:\s*\{[^{}]*?"enabled"\s*:\s*(true|false)')
    if ($m.Success) { $enabled = $m.Groups[1].Value -eq 'true' }
    $m = [regex]::Match($Text, '"hardware_acceleration_mode_previous"\s*:\s*(true|false)')
    if ($m.Success) { $previous = $m.Groups[1].Value -eq 'true' }
    return @{ running = $previous; pending = $enabled }
}

# Insert `"key":value` as the first member of the object whose `{` ends at $BraceEnd.
function Add-JsonMember([string]$Text, [int]$BraceEnd, [string]$Member) {
    $rest = $Text.Substring($BraceEnd)
    $sep = if ($rest -match '^\s*\}') { '' } else { ',' }
    return $Text.Substring(0, $BraceEnd) + $Member + $sep + $rest
}

# Returns $Text with hardware acceleration set to $Enabled. Edits only the two keys and
# leaves the rest of the file byte-for-byte unchanged (no JSON round-trip).
function Set-HwAccelInText([string]$Text, [bool]$Enabled) {
    $v = if ($Enabled) { 'true' } else { 'false' }

    $m = [regex]::Match($Text, '"hardware_acceleration_mode"\s*:\s*\{[^{}]*?"enabled"\s*:\s*(true|false)')
    if ($m.Success) {
        $g = $m.Groups[1]
        $Text = $Text.Substring(0, $g.Index) + $v + $Text.Substring($g.Index + $g.Length)
    } else {
        $m = [regex]::Match($Text, '"hardware_acceleration_mode"\s*:\s*\{')
        if ($m.Success) {
            $Text = Add-JsonMember $Text ($m.Index + $m.Length) ('"enabled":' + $v)
        } else {
            $m = [regex]::Match($Text, '^\s*\{')
            if (-not $m.Success) { throw 'Local State is not a JSON object.' }
            $Text = Add-JsonMember $Text ($m.Index + $m.Length) ('"hardware_acceleration_mode":{"enabled":' + $v + '}')
        }
    }

    $m = [regex]::Match($Text, '"hardware_acceleration_mode_previous"\s*:\s*(true|false)')
    if ($m.Success) {
        $g = $m.Groups[1]
        $Text = $Text.Substring(0, $g.Index) + $v + $Text.Substring($g.Index + $g.Length)
    } else {
        $m = [regex]::Match($Text, '^\s*\{')
        $Text = Add-JsonMember $Text ($m.Index + $m.Length) ('"hardware_acceleration_mode_previous":' + $v)
    }
    return $Text
}

function Test-JsonText([string]$Text) {
    # Windows PowerShell 5.1: JavaScriptSerializer (case-sensitive keys, no size limit).
    $ser = $null
    try {
        Add-Type -AssemblyName System.Web.Extensions -ErrorAction Stop
        $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $ser.MaxJsonLength = [int]::MaxValue
        $ser.RecursionLimit = 1000
    } catch { $ser = $null }
    if ($ser) {
        try { $null = $ser.DeserializeObject($Text); return $true } catch { return $false }
    }
    # PowerShell 7: System.Text.Json.
    if ('System.Text.Json.JsonDocument' -as [type]) {
        try { ([System.Text.Json.JsonDocument]::Parse($Text)).Dispose(); return $true } catch { return $false }
    }
    try { $null = $Text | ConvertFrom-Json -ErrorAction Stop; return $true } catch { return $false }
}

function Read-HwAccelState([string]$LocalStatePath) {
    if (-not (Test-Path -LiteralPath $LocalStatePath)) { throw "Local State not found at '$LocalStatePath'." }
    return Get-HwAccelFromText ([System.IO.File]::ReadAllText($LocalStatePath, $script:Utf8NoBom))
}

function Set-HwAccelInFile([string]$LocalStatePath, [bool]$Enabled) {
    if (-not (Test-Path -LiteralPath $LocalStatePath)) { throw "Local State not found at '$LocalStatePath'." }
    $original = [System.IO.File]::ReadAllText($LocalStatePath, $script:Utf8NoBom)
    $updated = Set-HwAccelInText $original $Enabled
    if (-not (Test-JsonText $updated)) { throw 'Patched Local State is not valid JSON; left the file untouched.' }
    $check = Get-HwAccelFromText $updated
    if ($check.pending -ne $Enabled -or $check.running -ne $Enabled) { throw 'Patch verification failed; left the file untouched.' }
    Copy-Item -LiteralPath $LocalStatePath -Destination "$LocalStatePath.accelplugin.bak" -Force
    [System.IO.File]::WriteAllText($LocalStatePath, $updated, $script:Utf8NoBom)
}
