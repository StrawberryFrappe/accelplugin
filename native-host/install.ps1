# One-time setup: registers host.bat as a native messaging host for the browsers you pick.
# Run install.bat (double-click). No admin rights needed; everything goes to HKCU.
# Run it again any time to change the selection.
#
# Non-interactive: install.ps1 -Browsers operagx,firefox
param(
    [string[]]$Browsers,
    [string]$ExtensionId = 'lbheolnljihmphgebojmlbifcfmchhnk',
    [string]$FirefoxExtensionId = 'hw-accel-toggler@accelplugin'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

Write-Host 'HW Accel Toggler - helper setup' -ForegroundColor Cyan
Write-Host ''

# Files extracted from a downloaded zip are marked as "from the internet".
try { Get-ChildItem -Path $PSScriptRoot -File | Unblock-File -ErrorAction SilentlyContinue } catch { }

$defs = Get-BrowserDefs
$ids = @($defs.Keys)
$found = @{}
foreach ($id in $ids) { $found[$id] = Find-BrowserInstallDir $defs[$id] }

# Turns "1,3", "1 3", "operagx, firefox" or "Opera GX" into browser ids. $null if anything is invalid.
function ConvertTo-BrowserIds([string[]]$Answer) {
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($part in ($Answer -join ',') -split '[,;]+') {
        $p = $part.Trim()
        if (-not $p) { continue }
        $match = $null
        if ($p -match '^\d+$' -and [int]$p -ge 1 -and [int]$p -le $ids.Count) { $match = $ids[[int]$p - 1] }
        else { $match = $ids | Where-Object { $_ -eq $p -or $defs[$_].name -eq $p } | Select-Object -First 1 }
        if (-not $match) { return $null }
        if (-not $result.Contains($match)) { $result.Add($match) }
    }
    if (-not $result.Count) { return $null }
    return , $result.ToArray()
}

$selected = if ($Browsers) { ConvertTo-BrowserIds $Browsers } else { $null }
if ($Browsers -and -not $selected) { throw "Unknown browser in '$($Browsers -join ',')'. Use: $($ids -join ', ')." }
if (-not $selected) {
    Write-Host 'Which browsers should the helper work with?'
    for ($i = 0; $i -lt $ids.Count; $i++) {
        $id = $ids[$i]
        $status = if ($found[$id]) { "found: $($found[$id])" } else { 'not found' }
        Write-Host ('  {0}) {1,-14} {2}' -f ($i + 1), $defs[$id].name, $status)
    }
    while (-not $selected) {
        $selected = ConvertTo-BrowserIds (Read-Host 'Type the numbers, separated by commas (e.g. 1 or 1,4)')
        if (-not $selected) { Write-Warning 'Please type one or more of the numbers above.' }
    }
}
Write-Host ''

$entries = [ordered]@{}
foreach ($id in $selected) {
    $def = $defs[$id]
    Write-Host $def.name -ForegroundColor Cyan

    $installDir = $found[$id]
    while (-not $installDir) {
        $answer = Read-Host "  Couldn't find $($def.name). Paste the folder that contains $($def.exe) (or the full path to it), or press Enter to skip"
        if (-not $answer.Trim()) { break }
        $installDir = Resolve-BrowserInstallDir $def $answer
        if (-not $installDir) { Write-Warning "  No $($def.exe) there." }
    }
    if (-not $installDir) { Write-Warning "  Skipped $($def.name)."; continue }

    $settings = Get-DefaultSettingsPath $def
    while (-not ($settings -and (Test-Path -LiteralPath $settings))) {
        $answer = Read-Host "  Couldn't find its $(Get-SettingsFileName $def). $($def.profileHint), or press Enter to skip"
        if (-not $answer.Trim()) { $settings = $null; break }
        $settings = Resolve-SettingsPath $def $answer
        if (-not $settings) { Write-Warning "  No $(Get-SettingsFileName $def) there." }
    }
    if (-not $settings) { Write-Warning "  Skipped $($def.name)."; continue }

    $state = Read-BrowserHwState $def $settings
    Write-Host "  Install:   $installDir"
    Write-Host "  Restarts:  $(Get-BrowserLauncher $def $installDir)"
    Write-Host "  Settings:  $settings"
    Write-Host "  Hardware acceleration is currently $(if ($state.running) { 'ON' } else { 'OFF' })."
    if ($state.warning) { Write-Warning "  $($state.warning)" }
    $entries[$id] = @{ def = $def; installDir = $installDir; settings = $settings }
}

if (-not $entries.Count) { throw 'No browser was set up.' }
Save-AccelConfig $entries

# Start from a clean slate so browsers dropped from the selection stop seeing the helper.
Remove-AccelRegistration

$hostBat = Join-Path $PSScriptRoot 'host.bat'
$chromiumManifest = Join-Path $PSScriptRoot "$script:AccelHostName.json"
$firefoxManifest = Join-Path $PSScriptRoot "$script:AccelHostName.firefox.json"
$description = 'HW Accel Toggler helper'

foreach ($id in $entries.Keys) {
    $def = $defs[$id]
    if ($def.kind -eq 'firefox') {
        $manifestPath = $firefoxManifest
        $manifest = [ordered]@{ name = $script:AccelHostName; description = $description; path = $hostBat; type = 'stdio'; allowed_extensions = @($FirefoxExtensionId) }
    } else {
        $manifestPath = $chromiumManifest
        $manifest = [ordered]@{ name = $script:AccelHostName; description = $description; path = $hostBat; type = 'stdio'; allowed_origins = @("chrome-extension://$ExtensionId/") }
    }
    [System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json), $script:Utf8NoBom)
    foreach ($root in $def.registry) {
        New-Item -Path "$root\NativeMessagingHosts\$script:AccelHostName" -Value $manifestPath -Force | Out-Null
    }
}

Write-Host ''
Write-Host "Done. Set up for: $(($entries.Keys | ForEach-Object { $defs[$_].name }) -join ', ')." -ForegroundColor Green
Write-Host 'Restart each of those browsers once, then open the extension''s settings and click "Test helper".'
Write-Host 'If you move this folder, or want to change the browsers, run install.bat again.'
