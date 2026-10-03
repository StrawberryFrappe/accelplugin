# Removes the native messaging host registration and files created by install.ps1.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

Remove-AccelRegistration
foreach ($f in "$script:AccelHostName.json", "$script:AccelHostName.firefox.json", 'config.json') {
    $p = Join-Path $PSScriptRoot $f
    if (Test-Path $p) { Remove-Item -LiteralPath $p -Force }
}
Write-Host 'Helper unregistered from all browsers. You can now remove the extension and delete this folder.' -ForegroundColor Green
