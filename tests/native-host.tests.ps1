# Tests for native-host/common.ps1 and the host.ps1 protocol.
# Run: pwsh -NoProfile -File tests/native-host.tests.ps1   (works on Windows PowerShell 5.1 too)
$ErrorActionPreference = 'Stop'
if (-not $env:LOCALAPPDATA) { $env:LOCALAPPDATA = [System.IO.Path]::GetTempPath() }
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'native-host/common.ps1')

$script:failures = 0
function Check([string]$Name, [bool]$Cond) {
    if ($Cond) { Write-Host "ok   $Name" } else { Write-Host "FAIL $Name" -ForegroundColor Red; $script:failures++ }
}

# --- Get/Set in text -----------------------------------------------------------
$cases = @(
    @{ name = 'key absent'; text = '{"browser":{"enabled_labs_experiments":[]},"user_experience_metrics":{"x":1}}' },
    @{ name = 'key true'; text = '{"a":1,"hardware_acceleration_mode":{"enabled":true},"hardware_acceleration_mode_previous":true,"z":[1,2]}' },
    @{ name = 'key false'; text = '{"hardware_acceleration_mode":{"enabled":false},"hardware_acceleration_mode_previous":false}' },
    @{ name = 'empty object'; text = '{}' },
    @{ name = 'empty inner object'; text = '{"hardware_acceleration_mode":{},"b":2}' },
    @{ name = 'pretty printed'; text = "{`n  `"hardware_acceleration_mode`" : { `"enabled`" : true },`n  `"hardware_acceleration_mode_previous`" : true`n}" },
    @{ name = 'previous only'; text = '{"x":{"y":"}"},"hardware_acceleration_mode_previous":false}' }
)
foreach ($c in $cases) {
    foreach ($target in $true, $false) {
        $out = Set-HwAccelInText $c.text $target
        $s = Get-HwAccelFromText $out
        Check "$($c.name) -> $target : valid JSON" (Test-JsonText $out)
        Check "$($c.name) -> $target : pending=$target" ($s.pending -eq $target)
        Check "$($c.name) -> $target : running=$target" ($s.running -eq $target)
        Check "$($c.name) -> $target : idempotent" ((Set-HwAccelInText $out $target) -eq $out)
    }
}

$untouched = '{"a":{"b":[1,2,{"c":"d"}]},"hardware_acceleration_mode":{"enabled":true},"big":12345678901234567890,"u":"\u00e9"}'
$out = Set-HwAccelInText $untouched $false
Check 'only the setting changes' ($out -eq '{"hardware_acceleration_mode_previous":false,"a":{"b":[1,2,{"c":"d"}]},"hardware_acceleration_mode":{"enabled":false},"big":12345678901234567890,"u":"\u00e9"}')
Check 'previous key is not confused with main key' ((Get-HwAccelFromText '{"hardware_acceleration_mode_previous":false}').pending -eq $true)
Check 'defaults are on' ((Get-HwAccelFromText '{}').running -and (Get-HwAccelFromText '{}').pending)
Check 'invalid JSON detected' (-not (Test-JsonText '{"a":'))
Check 'case-different keys are valid JSON' (Test-JsonText '{"a":1,"A":2}')
$threw = $false; try { Set-HwAccelInText '[1,2]' $false } catch { $threw = $true }
Check 'non-object rejected' $threw

# --- Set in file ---------------------------------------------------------------
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("accel-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    $ls = Join-Path $tmp 'Local State'
    [System.IO.File]::WriteAllText($ls, $cases[1].text, $script:Utf8NoBom)
    Set-HwAccelInFile $ls $false
    Check 'file: updated' (-not (Read-HwAccelState $ls).pending)
    Check 'file: backup written' ((Get-Content -Raw "$ls.accelplugin.bak") -eq $cases[1].text)
    Check 'file: no BOM' ([System.IO.File]::ReadAllBytes($ls)[0] -eq [byte][char]'{')

    [System.IO.File]::WriteAllText($ls, 'not json', $script:Utf8NoBom)
    $threw = $false; try { Set-HwAccelInFile $ls $false } catch { $threw = $true }
    Check 'file: invalid file left untouched' ($threw -and (Get-Content -Raw $ls) -eq 'not json')

    # --- install folder detection (layout from a real Opera GX 136 install) ---------
    $gx = Join-Path $tmp 'Opera GX'
    foreach ($d in '136.0.6008.67', '136.0.6008.76', '130.0.5847.89', 'autoupdate') { New-Item -ItemType Directory -Path (Join-Path $gx $d) | Out-Null }
    foreach ($f in 'opera.exe', '136.0.6008.67/opera.exe', '136.0.6008.76/opera.exe', '130.0.5847.89/debug.log') { Set-Content -Path (Join-Path $gx $f) -Value 'x' }
    $sep = [System.IO.Path]::DirectorySeparatorChar
    Check 'resolve: install folder' ((Resolve-GxInstallDir $gx) -eq $gx)
    Check 'resolve: opera.exe in install folder' ((Resolve-GxInstallDir (Join-Path $gx 'opera.exe')) -eq $gx)
    Check 'resolve: versioned folder -> install folder' ((Resolve-GxInstallDir (Join-Path $gx '136.0.6008.76')) -eq $gx)
    Check 'resolve: versioned opera.exe -> install folder' ((Resolve-GxInstallDir (Join-Path $gx '136.0.6008.67/opera.exe')) -eq $gx)
    Check 'resolve: quotes and trailing separator' ((Resolve-GxInstallDir ('  "' + $gx + $sep + '" ')) -eq $gx)
    Check 'resolve: folder without exe' ($null -eq (Resolve-GxInstallDir (Join-Path $gx 'autoupdate')))
    Check 'resolve: missing path' ($null -eq (Resolve-GxInstallDir (Join-Path $tmp 'nope')))
    Check 'resolve: empty' ($null -eq (Resolve-GxInstallDir ''))
    Check 'launcher: opera.exe in install folder' ((Get-GxLauncher $gx) -eq (Join-Path $gx 'opera.exe'))
    $old = Join-Path $tmp 'Old GX'
    New-Item -ItemType Directory -Path $old | Out-Null
    Set-Content -Path (Join-Path $old 'launcher.exe') -Value 'x'; Set-Content -Path (Join-Path $old 'opera.exe') -Value 'x'
    Check 'launcher: launcher.exe preferred on older installs' ((Get-GxLauncher $old) -eq (Join-Path $old 'launcher.exe'))

    # --- host.ps1 protocol: getState --------------------------------------------
    [System.IO.File]::WriteAllText($ls, $cases[2].text, $script:Utf8NoBom)
    $hostDir = Join-Path $tmp 'host'
    Copy-Item (Join-Path $root 'native-host') $hostDir -Recurse
    [System.IO.File]::WriteAllText((Join-Path $hostDir 'config.json'), (@{ installDir = (Join-Path $gx '136.0.6008.76'); localState = $ls } | ConvertTo-Json), $script:Utf8NoBom)

    function Invoke-Host([string]$Json) {
        $body = [System.Text.Encoding]::UTF8.GetBytes($Json)
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = (Get-Process -Id $PID).Path
        $psi.Arguments = "-NoProfile -File `"$(Join-Path $hostDir 'host.ps1')`""
        $psi.UseShellExecute = $false
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        $p.StandardInput.BaseStream.Write([BitConverter]::GetBytes([int32]$body.Length), 0, 4)
        $p.StandardInput.BaseStream.Write($body, 0, $body.Length)
        $p.StandardInput.Close()
        $ms = New-Object System.IO.MemoryStream
        $p.StandardOutput.BaseStream.CopyTo($ms)
        $p.WaitForExit()
        $bytes = $ms.ToArray()
        $len = [BitConverter]::ToInt32($bytes, 0)
        Check "host: length prefix matches ($len)" ($len -eq $bytes.Length - 4)
        return [System.Text.Encoding]::UTF8.GetString($bytes, 4, $bytes.Length - 4) | ConvertFrom-Json
    }

    $r = Invoke-Host '{"cmd":"getState"}'
    Check 'host: getState ok' ($r.ok -eq $true -and $r.running -eq $false -and $r.pending -eq $false)
    $r = Invoke-Host '{"cmd":"bogus"}'
    Check 'host: unknown command reports error' ($r.ok -eq $false -and $r.error -match 'Unknown command')
    $r = Invoke-Host '{"cmd":"apply","enabled":"yes"}'
    Check 'host: apply validates input' ($r.ok -eq $false -and $r.error -match 'enabled')
} finally {
    Remove-Item -Recurse -Force $tmp
}

if ($script:failures) { Write-Host "$script:failures check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'All checks passed' -ForegroundColor Green
