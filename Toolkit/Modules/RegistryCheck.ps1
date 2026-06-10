# Registry audit: autoruns, logon hijacks, IFEO debuggers, suspicious services.
function Invoke-RegistryCheck {
    param([string]$Target, [bool]$IsWinPE)

    $loaded = @()
    try {
        if ($IsWinPE) {
            Write-RLog "Loading offline registry hives from $Target ..."
            reg load 'HKLM\OFFLINE_SOFTWARE' "$Target\Windows\System32\config\SOFTWARE" | Out-Null
            reg load 'HKLM\OFFLINE_SYSTEM'   "$Target\Windows\System32\config\SYSTEM"   | Out-Null
            $loaded = @('HKLM\OFFLINE_SOFTWARE', 'HKLM\OFFLINE_SYSTEM')
            $sw = 'HKLM:\OFFLINE_SOFTWARE'
            $sys = 'HKLM:\OFFLINE_SYSTEM\ControlSet001'
            $userHives = @()  # per-user hives could be loaded from $Target\Users\*\NTUSER.DAT
        } else {
            $sw  = 'HKLM:\SOFTWARE'
            $sys = 'HKLM:\SYSTEM\CurrentControlSet'
            $userHives = @('HKCU:')
        }

        Write-RLog '--- Autorun entries (Run / RunOnce) ---'
        $runKeys = @("$sw\Microsoft\Windows\CurrentVersion\Run",
                     "$sw\Microsoft\Windows\CurrentVersion\RunOnce",
                     "$sw\WOW6432Node\Microsoft\Windows\CurrentVersion\Run") +
                   ($userHives | ForEach-Object { "$_\Software\Microsoft\Windows\CurrentVersion\Run" })
        foreach ($k in $runKeys) {
            if (-not (Test-Path $k)) { continue }
            (Get-Item $k).Property | ForEach-Object {
                $val = (Get-ItemProperty $k).$_
                $flag = if ($val -match '\\Temp\\|\\AppData\\Local\\Temp|powershell.*-enc|wscript|mshta|\.vbs|\.js"?\s*$') { '  <== SUSPICIOUS' } else { '' }
                Write-RLog ("  [{0}] {1} = {2}{3}" -f $k.Split('\')[-1], $_, $val, $flag)
            }
        }

        Write-RLog '--- Winlogon shell / userinit (hijack check) ---'
        $wl = Get-ItemProperty "$sw\Microsoft\Windows NT\CurrentVersion\Winlogon" -ErrorAction SilentlyContinue
        if ($wl) {
            $shellOk = $wl.Shell -match '^explorer\.exe$'
            $initOk  = $wl.Userinit -match 'userinit\.exe,?\s*$'
            Write-RLog ("  Shell    = {0} {1}" -f $wl.Shell,    $(if ($shellOk) { '(OK)' } else { '<== MODIFIED' }))
            Write-RLog ("  Userinit = {0} {1}" -f $wl.Userinit, $(if ($initOk)  { '(OK)' } else { '<== MODIFIED' }))
        }

        Write-RLog '--- Image File Execution Options debuggers (process hijack check) ---'
        $ifeo = "$sw\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
        $hits = 0
        Get-ChildItem $ifeo -ErrorAction SilentlyContinue | ForEach-Object {
            $dbg = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).Debugger
            if ($dbg) { Write-RLog "  $($_.PSChildName) -> Debugger = $dbg  <== REVIEW"; $hits++ }
        }
        if (-not $hits) { Write-RLog '  None found (good).' }

        Write-RLog '--- Services running from unusual locations ---'
        $hits = 0
        Get-ChildItem "$sys\Services" -ErrorAction SilentlyContinue | ForEach-Object {
            $img = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).ImagePath
            if ($img -and $img -match '\\Temp\\|\\AppData\\|\\Users\\Public\\|\\ProgramData\\(?!Microsoft)') {
                Write-RLog "  $($_.PSChildName): $img  <== REVIEW"; $hits++
            }
        }
        if (-not $hits) { Write-RLog '  None found (good).' }
        Write-RLog 'Registry check complete. Lines marked <== deserve manual review; do not delete blindly.'
    } finally {
        foreach ($h in $loaded) { reg unload $h 2>$null | Out-Null }
    }
}
