# Hardware/OS health diagnostics: disk SMART, system file integrity, RAM, events.
function Invoke-Diagnostics {
    param([string]$Target, [bool]$IsWinPE)

    Write-RLog '--- Disk health (SMART) ---'
    try {
        Get-PhysicalDisk | ForEach-Object {
            $rel = $_ | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
            $warn = if ($_.HealthStatus -ne 'Healthy') { '  <== ATTENTION' } else { '' }
            Write-RLog ("  {0}: {1}, {2:N0} GB{3}" -f $_.FriendlyName, $_.HealthStatus, ($_.Size / 1GB), $warn)
            if ($rel.ReadErrorsUncorrected) { Write-RLog "    Uncorrected read errors: $($rel.ReadErrorsUncorrected) <== failing media" }
            if ($rel.Temperature) { Write-RLog "    Temperature: $($rel.Temperature) C" }
        }
    } catch { Write-RLog "  SMART query failed: $($_.Exception.Message)" }

    Write-RLog '--- Volume free space ---'
    [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady } | ForEach-Object {
        $pct = if ($_.TotalSize) { 100 * $_.TotalFreeSpace / $_.TotalSize } else { 0 }
        $warn = if ($pct -lt 10) { '  <== LOW SPACE' } else { '' }
        Write-RLog ("  {0} {1:N1} GB free of {2:N1} GB ({3:N0}%){4}" -f $_.Name, ($_.TotalFreeSpace/1GB), ($_.TotalSize/1GB), $pct, $warn)
    }

    Write-RLog '--- System file integrity (sfc) — this takes several minutes ---'
    if ($IsWinPE) {
        $boot = ($Target -replace ':$', ':') + '\'
        $p = Start-Process sfc -ArgumentList "/scannow /offbootdir=$boot /offwindir=$Target\Windows" -NoNewWindow -Wait -PassThru
    } else {
        $p = Start-Process sfc -ArgumentList '/scannow' -NoNewWindow -Wait -PassThru
    }
    Write-RLog "  sfc finished (exit $($p.ExitCode)); details in $Target\Windows\Logs\CBS\CBS.log"

    Write-RLog '--- Component store health (DISM ScanHealth) ---'
    $dismArgs = if ($IsWinPE) { "/Image:$Target\ /Cleanup-Image /ScanHealth" }
                else          { '/Online /Cleanup-Image /ScanHealth' }
    $p = Start-Process dism -ArgumentList $dismArgs -NoNewWindow -Wait -PassThru
    Write-RLog "  DISM finished (exit $($p.ExitCode)). If corruption was reported, run RestoreHealth from the console."

    if (-not $IsWinPE) {
        Write-RLog '--- Recent critical/error events (last 7 days, top 15) ---'
        try {
            Get-WinEvent -FilterHashtable @{ LogName = 'System'; Level = 1, 2; StartTime = (Get-Date).AddDays(-7) } `
                -MaxEvents 15 -ErrorAction Stop | ForEach-Object {
                Write-RLog ("  {0:MM-dd HH:mm} [{1}] {2}" -f $_.TimeCreated, $_.ProviderName,
                    ($_.Message -split "`n")[0].Trim())
            }
        } catch { Write-RLog '  No critical/error events in the last 7 days.' }

        if ([System.Windows.Forms.MessageBox]::Show(
            'Schedule a RAM test (Windows Memory Diagnostic) on next reboot?', 'Diagnostics', 'YesNo') -eq 'Yes') {
            Start-Process mdsched -ArgumentList '' -ErrorAction SilentlyContinue
        }
        try {
            $null = Get-CimInstance Win32_Battery -ErrorAction Stop
            powercfg /batteryreport /output "$env:TEMP\battery.html" | Out-Null
            Write-RLog "  Battery report: $env:TEMP\battery.html"
        } catch { }
    }
    Write-RLog 'Diagnostics complete.'
}
