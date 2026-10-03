# Shared helpers for host.ps1, apply.ps1, install.ps1 and uninstall.ps1. Dot-source this file.
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

# ------------------------------------------------------------------ supported browsers

$script:ChromiumExtensionId = 'lbheolnljihmphgebojmlbifcfmchhnk'
$script:FirefoxExtensionId = 'hw-accel-toggler@accelplugin'

function Join-PathSafe([string]$Base, [string]$Child) {
    if (-not $Base) { return $null }
    return Join-Path $Base $Child
}

# Everything the helper needs to know about each browser it supports.
#   kind         chromium: setting in <userDataDir>\Local State; firefox: setting in <profile>\prefs.js
#   exe          process name; the main process is the one without a child-process switch
#   launchers    files in the install folder that start the browser, in order of preference
#   registry     HKCU roots whose NativeMessagingHosts key the browser reads
function Get-BrowserDefs {
    $local = $env:LOCALAPPDATA
    $pf = $env:ProgramFiles
    $pf86 = ${env:ProgramFiles(x86)}
    return [ordered]@{
        operagx = @{
            id = 'operagx'; name = 'Opera GX'; kind = 'chromium'; exe = 'opera.exe'
            launchers = @('launcher.exe', 'opera.exe'); pathLike = '*\Opera GX\*'; uninstallName = 'Opera GX*'
            installDirs = @((Join-PathSafe $local 'Programs\Opera GX'), (Join-PathSafe $pf 'Opera GX'))
            userDataDir = Join-PathSafe $env:APPDATA 'Opera Software\Opera GX Stable'
            profileHint = 'Open opera://about in Opera GX and paste the "Profile" path'
            registry = @('HKCU:\Software\Opera Software', 'HKCU:\Software\Google\Chrome', 'HKCU:\Software\Chromium')
            relaunchArgs = @('--restore-last-session')
        }
        chrome = @{
            id = 'chrome'; name = 'Google Chrome'; kind = 'chromium'; exe = 'chrome.exe'
            launchers = @('chrome.exe'); pathLike = '*\Google\Chrome\*'; uninstallName = 'Google Chrome'
            installDirs = @((Join-PathSafe $pf 'Google\Chrome\Application'), (Join-PathSafe $pf86 'Google\Chrome\Application'), (Join-PathSafe $local 'Google\Chrome\Application'))
            userDataDir = Join-PathSafe $local 'Google\Chrome\User Data'
            profileHint = 'Open chrome://version in Chrome and paste the "Profile Path"'
            registry = @('HKCU:\Software\Google\Chrome')
            relaunchArgs = @('--restore-last-session')
        }
        brave = @{
            id = 'brave'; name = 'Brave'; kind = 'chromium'; exe = 'brave.exe'
            launchers = @('brave.exe'); pathLike = '*\BraveSoftware\Brave-Browser\*'; uninstallName = 'Brave*'
            installDirs = @((Join-PathSafe $pf 'BraveSoftware\Brave-Browser\Application'), (Join-PathSafe $pf86 'BraveSoftware\Brave-Browser\Application'), (Join-PathSafe $local 'BraveSoftware\Brave-Browser\Application'))
            userDataDir = Join-PathSafe $local 'BraveSoftware\Brave-Browser\User Data'
            profileHint = 'Open brave://version in Brave and paste the "Profile Path"'
            registry = @('HKCU:\Software\BraveSoftware\Brave-Browser')
            relaunchArgs = @('--restore-last-session')
        }
        firefox = @{
            id = 'firefox'; name = 'Firefox'; kind = 'firefox'; exe = 'firefox.exe'
            launchers = @('firefox.exe'); pathLike = '*\Mozilla Firefox\*'; uninstallName = 'Mozilla Firefox*'
            installDirs = @((Join-PathSafe $pf 'Mozilla Firefox'), (Join-PathSafe $pf86 'Mozilla Firefox'), (Join-PathSafe $local 'Mozilla Firefox'))
            userDataDir = $null
            profileHint = 'Open about:support in Firefox and paste the "Profile Folder" path'
            registry = @('HKCU:\Software\Mozilla')
            # Session restore is requested through prefs.js (browser.sessionstore.resume_session_once).
            relaunchArgs = @()
        }
    }
}

function Get-BrowserDef([string]$Id) {
    $defs = Get-BrowserDefs
    if (-not $Id -or -not $defs.Contains($Id)) { throw "Unknown browser '$Id'." }
    return $defs[$Id]
}

# The file that holds the hardware acceleration setting.
function Get-SettingsFileName($Def) {
    if ($Def.kind -eq 'firefox') { return 'prefs.js' }
    return 'Local State'
}

function Get-DefaultSettingsPath($Def) {
    if ($Def.kind -eq 'firefox') {
        $profileDir = Get-FirefoxDefaultProfile
        if ($profileDir) { return Join-Path $profileDir 'prefs.js' }
        return $null
    }
    return Join-PathSafe $Def.userDataDir 'Local State'
}

# Accepts the settings file, the folder that holds it, or (for Chromium) a profile folder one
# level below it, as shown on chrome://version. Returns the settings file path, or $null.
function Resolve-SettingsPath($Def, [string]$Path) {
    if (-not $Path) { return $null }
    $p = $Path.Trim().Trim('"').Trim().TrimEnd('\', '/')
    if (-not $p) { return $null }
    $name = Get-SettingsFileName $Def
    if ((Split-Path -Leaf $p) -eq $name -and (Test-Path -LiteralPath $p -PathType Leaf)) { return $p }
    if (-not (Test-Path -LiteralPath $p -PathType Container)) { return $null }
    $candidate = Join-Path $p $name
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    if ($Def.kind -eq 'chromium') {
        $candidate = Join-Path (Split-Path -Parent $p) $name
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}

# Firefox: the profile the default installation uses, from %APPDATA%\Mozilla\Firefox\profiles.ini.
function Get-FirefoxDefaultProfile([string]$BaseDir = (Join-PathSafe $env:APPDATA 'Mozilla\Firefox')) {
    if (-not $BaseDir) { return $null }
    $ini = Join-Path $BaseDir 'profiles.ini'
    if (-not (Test-Path -LiteralPath $ini)) { return $null }
    $sections = [ordered]@{}
    $current = $null
    foreach ($line in [System.IO.File]::ReadAllLines($ini)) {
        $t = $line.Trim()
        if ($t -match '^\[(.+)\]$') { $current = [ordered]@{}; $sections[$Matches[1]] = $current }
        elseif ($null -ne $current -and $t -match '^([^=;#]+)=(.*)$') { $current[$Matches[1].Trim()] = $Matches[2].Trim() }
    }
    $profiles = @($sections.Keys | Where-Object { $_ -like 'Profile*' } | ForEach-Object { $sections[$_] })
    $path = $null
    foreach ($k in $sections.Keys) {
        if ($k -like 'Install*' -and $sections[$k]['Default']) { $path = $sections[$k]['Default']; break }
    }
    if (-not $path) {
        $default = $profiles | Where-Object { $_['Default'] -eq '1' } | Select-Object -First 1
        if (-not $default) { $default = $profiles | Select-Object -First 1 }
        if ($default) { $path = $default['Path'] }
    }
    if (-not $path) { return $null }
    $entry = $profiles | Where-Object { $_['Path'] -eq $path } | Select-Object -First 1
    $relative = if ($entry) { $entry['IsRelative'] -ne '0' } else { -not [System.IO.Path]::IsPathRooted($path) }
    $path = $path -replace '/', [string][System.IO.Path]::DirectorySeparatorChar
    if ($relative) { $path = Join-Path $BaseDir $path }
    return $path
}

# ------------------------------------------------------------------ install folders

function Test-BrowserInstallDir($Def, [string]$Dir) {
    foreach ($name in $Def.launchers) {
        if (Test-Path -LiteralPath (Join-Path $Dir $name)) { return $true }
    }
    return $false
}

# Accepts the install folder, a versioned subfolder, or the path to an exe in either (quotes
# and trailing slashes allowed). Returns the stable install folder, or $null.
# Opera GX keeps a copy of opera.exe in versioned subfolders (e.g. 136.0.6008.76\) that change
# with every update, so those resolve to the install folder above them.
function Resolve-BrowserInstallDir($Def, [string]$Path) {
    if (-not $Path) { return $null }
    $p = $Path.Trim().Trim('"').Trim().TrimEnd('\', '/')
    if (-not $p) { return $null }
    if (Test-Path -LiteralPath $p -PathType Leaf) { $p = Split-Path -Parent $p }
    if (-not (Test-Path -LiteralPath $p -PathType Container)) { return $null }
    if ((Split-Path -Leaf $p) -match '^\d+(\.\d+)+$') {
        $parent = Split-Path -Parent $p
        if ($parent -and (Test-BrowserInstallDir $Def $parent)) { return $parent }
    }
    if (Test-BrowserInstallDir $Def $p) { return $p }
    return $null
}

function Find-BrowserInstallDir($Def) {
    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($p in Get-BrowserProcesses $Def) {
        if ($p.ExecutablePath) { $candidates.Add($p.ExecutablePath) }
    }
    foreach ($key in 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
                     'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
                     'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*') {
        Get-ItemProperty $key -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like $Def.uninstallName -and $_.InstallLocation } |
            ForEach-Object { $candidates.Add($_.InstallLocation) }
    }
    foreach ($d in $Def.installDirs) { if ($d) { $candidates.Add($d) } }
    foreach ($c in $candidates) {
        $dir = Resolve-BrowserInstallDir $Def $c
        if ($dir) { return $dir }
    }
    return $null
}

function Get-BrowserLauncher($Def, [string]$InstallDir) {
    if (-not $InstallDir) { return $null }
    foreach ($name in $Def.launchers) {
        $p = Join-Path $InstallDir $name
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

# ------------------------------------------------------------------ processes

# All processes of this browser. With an install folder, only those running from it, so
# e.g. regular Opera is never touched when Opera GX is meant.
function Get-BrowserProcesses($Def, [string]$InstallDir) {
    $all = @()
    try { $all = @(Get-CimInstance Win32_Process -Filter "Name = '$($Def.exe)'" -ErrorAction Stop) } catch { }
    if ($InstallDir) {
        $prefix = $InstallDir.TrimEnd('\') + '\'
        return @($all | Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) })
    }
    return @($all | Where-Object { $_.ExecutablePath -like $Def.pathLike })
}

# The main process is the one without a child-process switch.
function Get-BrowserMainProcesses($Def, [string]$InstallDir) {
    $childSwitch = if ($Def.kind -eq 'firefox') { '-contentproc' } else { '--type=' }
    return @(Get-BrowserProcesses $Def $InstallDir | Where-Object { $_.CommandLine -notmatch [regex]::Escape($childSwitch) })
}

# ------------------------------------------------------------------ config

# config.json, written by install.ps1:
#   { "browsers": { "<id>": { "installDir": "...", "settings": "...\\Local State" } } }
# The first version stored a single Opera GX entry as { "installDir", "localState" }.
function Get-AccelConfig {
    $result = [ordered]@{}
    $path = Join-Path $PSScriptRoot 'config.json'
    if (-not (Test-Path $path)) { return $result }
    $saved = [System.IO.File]::ReadAllText($path) | ConvertFrom-Json
    $entries = @{}
    if ($saved.browsers) {
        foreach ($prop in $saved.browsers.PSObject.Properties) { $entries[$prop.Name] = $prop.Value }
    } elseif ($saved.installDir -or $saved.localState) {
        $entries['operagx'] = [pscustomobject]@{ installDir = $saved.installDir; settings = $saved.localState }
    }
    $defs = Get-BrowserDefs
    foreach ($id in $defs.Keys) {
        if (-not $entries.ContainsKey($id)) { continue }
        $def = $defs[$id]
        $e = $entries[$id]
        $installDir = Resolve-BrowserInstallDir $def $e.installDir
        if (-not $installDir) { $installDir = Find-BrowserInstallDir $def }
        $settings = if ($e.settings) { $e.settings } else { Get-DefaultSettingsPath $def }
        $result[$id] = @{ def = $def; installDir = $installDir; settings = $settings }
    }
    return $result
}

function Save-AccelConfig($Entries) {
    $browsers = [ordered]@{}
    foreach ($id in $Entries.Keys) {
        $browsers[$id] = [ordered]@{ installDir = $Entries[$id].installDir; settings = $Entries[$id].settings }
    }
    $json = [ordered]@{ browsers = $browsers } | ConvertTo-Json -Depth 4
    [System.IO.File]::WriteAllText((Join-Path $PSScriptRoot 'config.json'), $json, $script:Utf8NoBom)
}

# Work out which configured browser started this host: walk up the process tree looking for
# an exe inside a configured install folder; otherwise trust the extension's hint.
function Resolve-CallingBrowser($Config, [string]$Hint) {
    if (-not $Config.Count) { throw 'The helper has no browsers set up. Run native-host\install.bat.' }
    try {
        $proc = Get-CimInstance Win32_Process -Filter "ProcessId = $PID" -ErrorAction Stop
        for ($i = 0; $i -lt 5 -and $proc; $i++) {
            $proc = Get-CimInstance Win32_Process -Filter "ProcessId = $($proc.ParentProcessId)" -ErrorAction Stop
            if (-not $proc -or -not $proc.ExecutablePath) { continue }
            foreach ($id in $Config.Keys) {
                $dir = $Config[$id].installDir
                if ($dir -and $proc.ExecutablePath.StartsWith($dir.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { return $id }
            }
        }
    } catch { }
    if ($Hint) {
        if ($Config.Contains($Hint)) { return $Hint }
        $name = $Hint
        try { $name = (Get-BrowserDef $Hint).name } catch { }
        throw "The helper isn't set up for $name. Run native-host\install.bat and select it."
    }
    if ($Config.Count -eq 1) { return @($Config.Keys)[0] }
    throw 'Could not tell which browser is calling the helper.'
}

# ------------------------------------------------------------------ dispatch by browser kind

function Read-BrowserHwState($Def, [string]$SettingsPath) {
    if (-not $SettingsPath -or -not (Test-Path -LiteralPath $SettingsPath)) {
        throw "$($Def.name) settings file not found at '$SettingsPath'. Run native-host\install.bat again."
    }
    if ($Def.kind -eq 'firefox') { return Read-FirefoxHwAccelState $SettingsPath }
    return Read-HwAccelState $SettingsPath
}

function Set-BrowserHwState($Def, [string]$SettingsPath, [bool]$Enabled) {
    if ($Def.kind -eq 'firefox') { Set-FirefoxHwAccelInFile $SettingsPath $Enabled }
    else { Set-HwAccelInFile $SettingsPath $Enabled }
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

# ------------------------------------------------------------------ Firefox prefs.js

# Firefox's "Use hardware acceleration when available" checkbox is the pref
# layers.acceleration.disabled (default false). It shows only when "Use recommended
# performance settings" (browser.preferences.defaultPerformanceSettings.enabled) is off.
# prefs.js holds one `user_pref("name", value);` line per changed pref and is rewritten when
# Firefox exits, so like Local State it is only edited while Firefox is closed.

function Get-FirefoxPrefRegex([string]$Name) {
    return '(?m)^[ \t]*user_pref\(\s*"' + [regex]::Escape($Name) + '"\s*,\s*(.*?)\s*\)\s*;[^\r\n]*(\r?\n)?'
}

function Get-FirefoxPrefFromText([string]$Text, [string]$Name) {
    $m = [regex]::Match($Text, (Get-FirefoxPrefRegex $Name))
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

# Remove every line for $Name, then append one with $Value (a JS literal) unless $Value is $null.
function Set-FirefoxPrefInText([string]$Text, [string]$Name, $Value) {
    $Text = [regex]::Replace($Text, (Get-FirefoxPrefRegex $Name), '')
    if ($null -eq $Value) { return $Text }
    $nl = if ($Text -match "`r`n") { "`r`n" } else { "`n" }
    if ($Text.Length -and -not $Text.EndsWith("`n")) { $Text += $nl }
    return $Text + 'user_pref("' + $Name + '", ' + $Value + ');' + $nl
}

function Get-FirefoxHwAccelFromText([string]$Text) {
    $enabled = (Get-FirefoxPrefFromText $Text 'layers.acceleration.disabled') -ne 'true'
    return @{ running = $enabled; pending = $enabled }
}

function Set-FirefoxHwAccelInText([string]$Text, [bool]$Enabled) {
    if ($Enabled) {
        $Text = Set-FirefoxPrefInText $Text 'layers.acceleration.disabled' $null
    } else {
        $Text = Set-FirefoxPrefInText $Text 'layers.acceleration.disabled' 'true'
        # Show the checkbox in Settings, so it can be switched back by hand.
        $Text = Set-FirefoxPrefInText $Text 'browser.preferences.defaultPerformanceSettings.enabled' 'false'
    }
    # Reopen the windows and tabs on the next start, whatever the startup setting says.
    $Text = Set-FirefoxPrefInText $Text 'browser.sessionstore.resume_session_once' 'true'
    return $Text
}

function Read-FirefoxHwAccelState([string]$PrefsPath) {
    $state = Get-FirefoxHwAccelFromText ([System.IO.File]::ReadAllText($PrefsPath, $script:Utf8NoBom))
    # user.js overrides prefs.js on every start.
    $userJs = Join-Path (Split-Path -Parent $PrefsPath) 'user.js'
    if (Test-Path -LiteralPath $userJs) {
        $forced = Get-FirefoxPrefFromText ([System.IO.File]::ReadAllText($userJs, $script:Utf8NoBom)) 'layers.acceleration.disabled'
        if ($null -ne $forced) { $state.warning = "user.js in the Firefox profile forces layers.acceleration.disabled=$forced; the helper's changes won't stick." }
    }
    return $state
}

function Set-FirefoxHwAccelInFile([string]$PrefsPath, [bool]$Enabled) {
    if (-not (Test-Path -LiteralPath $PrefsPath)) { throw "prefs.js not found at '$PrefsPath'." }
    $original = [System.IO.File]::ReadAllText($PrefsPath, $script:Utf8NoBom)
    $updated = Set-FirefoxHwAccelInText $original $Enabled
    if ((Get-FirefoxHwAccelFromText $updated).pending -ne $Enabled) { throw 'Patch verification failed; left prefs.js untouched.' }
    Copy-Item -LiteralPath $PrefsPath -Destination "$PrefsPath.accelplugin.bak" -Force
    [System.IO.File]::WriteAllText($PrefsPath, $updated, $script:Utf8NoBom)
}

# ------------------------------------------------------------------ registration

function Get-AccelRegistryRoots {
    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($def in (Get-BrowserDefs).Values) {
        foreach ($r in $def.registry) { if (-not $roots.Contains($r)) { $roots.Add($r) } }
    }
    return $roots
}

# Removes every native messaging registration this helper may have created.
function Remove-AccelRegistration {
    foreach ($root in Get-AccelRegistryRoots) {
        $key = "$root\NativeMessagingHosts\$script:AccelHostName"
        if (Test-Path $key) { Remove-Item -Path $key -Force }
    }
}
