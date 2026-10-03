# One-time setup: registers host.bat as a native messaging host for the extension.
# Run install.bat (double-click). No admin rights needed; everything goes to HKCU.
param(
    [string]$ExtensionId = 'lbheolnljihmphgebojmlbifcfmchhnk',
    [string]$InstallDir,
    [string]$LocalState
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

Write-Host 'HW Accel Toggler - helper setup' -ForegroundColor Cyan

# Files extracted from a downloaded zip are marked as "from the internet".
Get-ChildItem -Path $PSScriptRoot -File | Unblock-File -ErrorAction SilentlyContinue

$InstallDir = if ($InstallDir) { Resolve-GxInstallDir $InstallDir } else { Find-GxInstallDir }
while (-not $InstallDir) {
    Write-Warning 'Could not find Opera GX automatically.'
    $answer = Read-Host 'Paste the Opera GX folder that contains opera.exe (or the full path to opera.exe)'
    $InstallDir = Resolve-GxInstallDir $answer
}
Write-Host "Opera GX:     $InstallDir"
Write-Host "Relaunches:   $(Get-GxLauncher $InstallDir)"

if (-not $LocalState) { $LocalState = Get-DefaultLocalStatePath }
while (-not (Test-Path -LiteralPath $LocalState)) {
    Write-Warning "Local State not found at '$LocalState'."
    $dir = (Read-Host 'Open opera://about in Opera GX and paste the "Profile" path').Trim('"', ' ')
    $LocalState = Join-Path $dir 'Local State'
    if (-not (Test-Path -LiteralPath $LocalState)) { $LocalState = Join-Path (Split-Path -Parent $dir) 'Local State' }
}
Write-Host "Local State:  $LocalState"

$config = [ordered]@{ installDir = $InstallDir; localState = $LocalState }
[System.IO.File]::WriteAllText((Join-Path $PSScriptRoot 'config.json'), ($config | ConvertTo-Json), $script:Utf8NoBom)

$manifestPath = Join-Path $PSScriptRoot "$script:AccelHostName.json"
$manifest = [ordered]@{
    name = $script:AccelHostName
    description = 'HW Accel Toggler helper'
    path = (Join-Path $PSScriptRoot 'host.bat')
    type = 'stdio'
    allowed_origins = @("chrome-extension://$ExtensionId/")
}
[System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json), $script:Utf8NoBom)

# Opera reads Chrome's registry location; the others are harmless extras.
foreach ($base in 'HKCU:\Software\Google\Chrome', 'HKCU:\Software\Chromium', 'HKCU:\Software\Opera Software') {
    $key = "$base\NativeMessagingHosts\$script:AccelHostName"
    New-Item -Path $key -Value $manifestPath -Force | Out-Null
}

$state = Read-HwAccelState $LocalState
Write-Host ''
Write-Host "Done. Hardware acceleration is currently $(if ($state.running) { 'ON' } else { 'OFF' })." -ForegroundColor Green
Write-Host 'In Opera GX, open the extension''s settings and click "Test helper" to check the connection.'
Write-Host "If you move this folder, run install.bat again."
