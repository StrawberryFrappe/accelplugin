# Removes the native messaging host registration created by install.ps1.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

foreach ($base in 'HKCU:\Software\Google\Chrome', 'HKCU:\Software\Chromium', 'HKCU:\Software\Opera Software') {
    $key = "$base\NativeMessagingHosts\$script:AccelHostName"
    if (Test-Path $key) { Remove-Item -Path $key -Force }
}
foreach ($f in "$script:AccelHostName.json", 'config.json') {
    $p = Join-Path $PSScriptRoot $f
    if (Test-Path $p) { Remove-Item -LiteralPath $p -Force }
}
Write-Host 'Helper unregistered. You can now remove the extension and delete this folder.' -ForegroundColor Green
