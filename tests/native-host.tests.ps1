# Tests for native-host/common.ps1 and the host.ps1 protocol.
# Run: pwsh -NoProfile -File tests/native-host.tests.ps1   (works on Windows PowerShell 5.1 too)
$ErrorActionPreference = 'Stop'
if (-not $env:LOCALAPPDATA) { $env:LOCALAPPDATA = [System.IO.Path]::GetTempPath() }
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'native-host/common.ps1')
$sep = [string][System.IO.Path]::DirectorySeparatorChar

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

# --- Firefox prefs.js -------------------------------------------------------------
$fxBase = "// Mozilla User Preferences`n`nuser_pref(`"app.update.lastUpdateTime`", 1700000000);`nuser_pref(`"browser.startup.page`", 1);`n"
$off = Set-FirefoxHwAccelInText $fxBase $false
Check 'fx: off -> disabled pref written' ((Get-FirefoxPrefFromText $off 'layers.acceleration.disabled') -eq 'true')
Check 'fx: off -> checkbox made visible' ((Get-FirefoxPrefFromText $off 'browser.preferences.defaultPerformanceSettings.enabled') -eq 'false')
Check 'fx: session restore requested' ((Get-FirefoxPrefFromText $off 'browser.sessionstore.resume_session_once') -eq 'true')
Check 'fx: state reads off' (-not (Get-FirefoxHwAccelFromText $off).running)
Check 'fx: other prefs kept' ($off.StartsWith($fxBase))
Check 'fx: off is idempotent' ((Set-FirefoxHwAccelInText $off $false) -eq $off)
$on = Set-FirefoxHwAccelInText $off $true
Check 'fx: on -> disabled pref removed' ($null -eq (Get-FirefoxPrefFromText $on 'layers.acceleration.disabled'))
Check 'fx: state reads on' ((Get-FirefoxHwAccelFromText $on).running)
Check 'fx: no empty pref lines' ($on -notmatch 'user_pref\("[^"]+",\s*\)')
Check 'fx: default (no line) is on' ((Get-FirefoxHwAccelFromText $fxBase).running)
$crlf = "user_pref(`"a`", 1);`r`n"
Check 'fx: keeps CRLF line endings' ((Set-FirefoxHwAccelInText $crlf $false) -notmatch "[^`r]`n")
Check 'fx: no trailing newline handled' ((Set-FirefoxHwAccelInText 'user_pref("a", 1);' $false) -match '^user_pref\("a", 1\);\n')

# --- browser table and paths --------------------------------------------------------
$defs = Get-BrowserDefs
Check 'defs: four browsers' ((@($defs.Keys) -join ',') -eq 'operagx,chrome,brave,firefox')
Check 'defs: Firefox reads prefs.js' ((Get-SettingsFileName $defs.firefox) -eq 'prefs.js')
Check 'defs: Chromium reads Local State' ((Get-SettingsFileName $defs.chrome) -eq 'Local State')
foreach ($d in $defs.Values) { Check "defs: $($d.id) has registry roots" ($d.registry.Count -ge 1) }
$threw = $false; try { Get-BrowserDef 'edge' } catch { $threw = $true }
Check 'defs: unknown browser rejected' $threw

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

    # --- Firefox profiles.ini -----------------------------------------------------
    $fxRoot = Join-Path $tmp 'Mozilla/Firefox'
    New-Item -ItemType Directory -Path (Join-Path $fxRoot 'Profiles/abc.default-release') -Force | Out-Null
    $ini = "[Profile1]`nName=default`nIsRelative=1`nPath=Profiles/old.default`nDefault=1`n`n[Profile0]`nName=default-release`nIsRelative=1`nPath=Profiles/abc.default-release`n`n[Install308046B0AF4A39CB]`nDefault=Profiles/abc.default-release`nLocked=1`n`n[General]`nStartWithLastProfile=1`nVersion=2`n"
    [System.IO.File]::WriteAllText((Join-Path $fxRoot 'profiles.ini'), $ini)
    $expected = Join-Path $fxRoot ('Profiles' + $sep + 'abc.default-release')
    Check 'profiles.ini: install default wins' ((Get-FirefoxDefaultProfile $fxRoot) -eq $expected)
    [System.IO.File]::WriteAllText((Join-Path $fxRoot 'profiles.ini'), "[Profile0]`nIsRelative=1`nPath=Profiles/x`n[Profile1]`nIsRelative=0`nPath=/abs/y`nDefault=1`n")
    Check 'profiles.ini: absolute default profile' ((Get-FirefoxDefaultProfile $fxRoot) -eq ('/abs/y' -replace '/', $sep))
    Check 'profiles.ini: missing file' ($null -eq (Get-FirefoxDefaultProfile (Join-Path $tmp 'none')))

    # --- settings path from user input ---------------------------------------------
    $ud = Join-Path $tmp 'User Data'
    New-Item -ItemType Directory -Path (Join-Path $ud 'Default') -Force | Out-Null
    Set-Content -Path (Join-Path $ud 'Local State') -Value '{}'
    $chromeDef = Get-BrowserDef 'chrome'
    Check 'settings: user data folder' ((Resolve-SettingsPath $chromeDef $ud) -eq (Join-Path $ud 'Local State'))
    Check 'settings: profile path from chrome://version' ((Resolve-SettingsPath $chromeDef (Join-Path $ud 'Default')) -eq (Join-Path $ud 'Local State'))
    Check 'settings: the file itself' ((Resolve-SettingsPath $chromeDef ('"' + (Join-Path $ud 'Local State') + '"')) -eq (Join-Path $ud 'Local State'))
    $p1 = Join-Path $tmp 'p1'; New-Item -ItemType Directory -Path $p1 | Out-Null; Set-Content (Join-Path $p1 'prefs.js') ''
    Check 'settings: firefox profile folder' ((Resolve-SettingsPath (Get-BrowserDef 'firefox') $p1) -eq (Join-Path $p1 'prefs.js'))
    Check 'settings: nothing there' ($null -eq (Resolve-SettingsPath $chromeDef (Join-Path $tmp 'nope')))

    # --- Firefox file edit -------------------------------------------------------------
    $prefsFile = Join-Path $p1 'prefs.js'
    [System.IO.File]::WriteAllText($prefsFile, $fxBase, $script:Utf8NoBom)
    Set-BrowserHwState (Get-BrowserDef 'firefox') $prefsFile $false
    Check 'fx file: now off' (-not (Read-BrowserHwState (Get-BrowserDef 'firefox') $prefsFile).running)
    Check 'fx file: backup written' ((Get-Content -Raw "$prefsFile.accelplugin.bak") -eq $fxBase)
    Set-Content -Path (Join-Path $p1 'user.js') -Value 'user_pref("layers.acceleration.disabled", false);'
    Check 'fx file: user.js override reported' ((Read-BrowserHwState (Get-BrowserDef 'firefox') $prefsFile).warning -match 'user.js')

    # --- install folder detection (layout from a real Opera GX 136 install) ---------
    $gxDef = Get-BrowserDef 'operagx'
    $gx = Join-Path $tmp 'Opera GX'
    foreach ($d in '136.0.6008.67', '136.0.6008.76', '130.0.5847.89', 'autoupdate') { New-Item -ItemType Directory -Path (Join-Path $gx $d) | Out-Null }
    foreach ($f in 'opera.exe', '136.0.6008.67/opera.exe', '136.0.6008.76/opera.exe', '130.0.5847.89/debug.log') { Set-Content -Path (Join-Path $gx $f) -Value 'x' }
    Check 'resolve: install folder' ((Resolve-BrowserInstallDir $gxDef $gx) -eq $gx)
    Check 'resolve: opera.exe in install folder' ((Resolve-BrowserInstallDir $gxDef (Join-Path $gx 'opera.exe')) -eq $gx)
    Check 'resolve: versioned folder -> install folder' ((Resolve-BrowserInstallDir $gxDef (Join-Path $gx '136.0.6008.76')) -eq $gx)
    Check 'resolve: versioned opera.exe -> install folder' ((Resolve-BrowserInstallDir $gxDef (Join-Path $gx '136.0.6008.67/opera.exe')) -eq $gx)
    Check 'resolve: quotes and trailing separator' ((Resolve-BrowserInstallDir $gxDef ('  "' + $gx + $sep + '" ')) -eq $gx)
    Check 'resolve: folder without exe' ($null -eq (Resolve-BrowserInstallDir $gxDef (Join-Path $gx 'autoupdate')))
    Check 'resolve: missing path' ($null -eq (Resolve-BrowserInstallDir $gxDef (Join-Path $tmp 'nope')))
    Check 'resolve: empty' ($null -eq (Resolve-BrowserInstallDir $gxDef ''))
    Check 'launcher: opera.exe in install folder' ((Get-BrowserLauncher $gxDef $gx) -eq (Join-Path $gx 'opera.exe'))
    $old = Join-Path $tmp 'Old GX'
    New-Item -ItemType Directory -Path $old | Out-Null
    Set-Content -Path (Join-Path $old 'launcher.exe') -Value 'x'; Set-Content -Path (Join-Path $old 'opera.exe') -Value 'x'
    Check 'launcher: launcher.exe preferred on older installs' ((Get-BrowserLauncher $gxDef $old) -eq (Join-Path $old 'launcher.exe'))

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

    # Config written by the first version: a single Opera GX entry.
    $r = Invoke-Host '{"cmd":"getState","browser":"operagx"}'
    Check 'host: old config format still works' ($r.ok -eq $true -and $r.browser -eq 'operagx' -and $r.running -eq $false)
    $r = Invoke-Host '{"cmd":"getState"}'
    Check 'host: getState without hint uses the only browser' ($r.ok -eq $true -and $r.running -eq $false -and $r.pending -eq $false)
    $r = Invoke-Host '{"cmd":"bogus"}'
    Check 'host: unknown command reports error' ($r.ok -eq $false -and $r.error -match 'Unknown command')
    $r = Invoke-Host '{"cmd":"apply","enabled":"yes","browser":"operagx"}'
    Check 'host: apply validates input' ($r.ok -eq $false -and $r.error -match 'enabled')

    # New config format with two browsers.
    $fxProfile = Join-Path $tmp 'fxprofile'
    New-Item -ItemType Directory -Path $fxProfile | Out-Null
    $fxPrefs = Join-Path $fxProfile 'prefs.js'
    [System.IO.File]::WriteAllText($fxPrefs, "// Mozilla User Preferences`nuser_pref(`"layers.acceleration.disabled`", true);`n", $script:Utf8NoBom)
    $fxDir = Join-Path $tmp 'Mozilla Firefox'
    New-Item -ItemType Directory -Path $fxDir | Out-Null
    Set-Content -Path (Join-Path $fxDir 'firefox.exe') -Value 'x'
    $cfg = @{ browsers = [ordered]@{ operagx = @{ installDir = $gx; settings = $ls }; firefox = @{ installDir = $fxDir; settings = $fxPrefs } } }
    [System.IO.File]::WriteAllText((Join-Path $hostDir 'config.json'), ($cfg | ConvertTo-Json -Depth 4), $script:Utf8NoBom)
    $r = Invoke-Host '{"cmd":"getState","browser":"firefox"}'
    Check 'host: firefox getState' ($r.ok -eq $true -and $r.browser -eq 'firefox' -and $r.browserName -eq 'Firefox' -and $r.running -eq $false)
    $r = Invoke-Host '{"cmd":"getState","browser":"operagx"}'
    Check 'host: opera getState with two browsers' ($r.ok -eq $true -and $r.browser -eq 'operagx')
    $r = Invoke-Host '{"cmd":"getState","browser":"brave"}'
    Check 'host: browser not selected is refused' ($r.ok -eq $false -and $r.error -match "isn't set up for Brave")
    $r = Invoke-Host '{"cmd":"getState"}'
    Check 'host: ambiguous caller is refused' ($r.ok -eq $false -and $r.error -match 'which browser')
} finally {
    Remove-Item -Recurse -Force $tmp
}

if ($script:failures) { Write-Host "$script:failures check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'All checks passed' -ForegroundColor Green
