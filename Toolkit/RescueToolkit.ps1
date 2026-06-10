<#
.SYNOPSIS
    Claude Rescue Toolkit GUI.
    Runs in two modes, detected automatically:
      - Online:  inside a normal Windows session (operates on the running OS)
      - Offline: inside WinPE booted from the rescue drive (operates on the
                 Windows installation found on the internal disk)
#>
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Continue'

$script:IsWinPE = Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT'

function Find-OfflineWindows {
    # Locate the offline Windows installation when running from WinPE.
    foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
        if ($d.DriveType -ne 'Fixed' -or -not $d.IsReady) { continue }
        if ($d.Name -like 'X:*') { continue }   # X: is the WinPE RAM disk
        if (Test-Path (Join-Path $d.Name 'Windows\System32\config\SOFTWARE')) {
            return $d.Name.TrimEnd('\')         # e.g. "C:"
        }
    }
    return $null
}
$script:TargetDrive = if ($IsWinPE) { Find-OfflineWindows } else { $env:SystemDrive }

# Load feature modules.
foreach ($m in Get-ChildItem (Join-Path $PSScriptRoot 'Modules') -Filter *.ps1) { . $m.FullName }

# ---------------------------------------------------------------- UI ----------
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Claude Rescue Toolkit' + $(if ($IsWinPE) { '  [BOOT MODE — offline repair]' } else { '' })
$form.Size = New-Object System.Drawing.Size(760, 560)
$form.StartPosition = 'CenterScreen'

$lblMode = New-Object System.Windows.Forms.Label
$lblMode.Location = '15,12'
$lblMode.AutoSize = $true
$lblMode.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$lblMode.Text = if ($IsWinPE) {
    if ($TargetDrive) { "Boot mode — repairing offline Windows on $TargetDrive" }
    else { 'Boot mode — NO Windows installation found (is the disk BitLocker-locked?)' }
} else { "Running inside Windows ($TargetDrive)" }
$lblMode.ForeColor = if ($IsWinPE) { 'DarkOrange' } else { 'DarkGreen' }

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = '15,215'
$txtLog.Size = '715,295'
$txtLog.Multiline = $true; $txtLog.ReadOnly = $true; $txtLog.ScrollBars = 'Vertical'
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 9)

function Write-RLog([string]$msg) {
    $txtLog.AppendText(("[{0:HH:mm:ss}] {1}`r`n" -f (Get-Date), $msg))
    [System.Windows.Forms.Application]::DoEvents()
}

function New-ToolButton([string]$text, [int]$x, [int]$y, [scriptblock]$action) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text; $b.Location = "$x,$y"; $b.Size = '170,40'
    $b.Add_Click({
        $this.Enabled = $false
        try { & $action } catch { Write-RLog "ERROR: $($_.Exception.Message)" }
        finally { $this.Enabled = $true }
    }.GetNewClosure())
    $form.Controls.Add($b)
    $b
}

# Row 1: scans and checks
New-ToolButton 'Malware Scan'    15 40  { Invoke-MalwareScan    -Target $script:TargetDrive -IsWinPE $script:IsWinPE } | Out-Null
New-ToolButton 'Registry Check'  195 40 { Invoke-RegistryCheck  -Target $script:TargetDrive -IsWinPE $script:IsWinPE } | Out-Null
New-ToolButton 'Diagnostics'     375 40 { Invoke-Diagnostics    -Target $script:TargetDrive -IsWinPE $script:IsWinPE } | Out-Null
New-ToolButton 'Temp Cleanup'    555 40 { Invoke-TempCleanup    -Target $script:TargetDrive -IsWinPE $script:IsWinPE } | Out-Null

# Row 2: consoles and report
New-ToolButton 'Open PowerShell' 15 90  { Start-Process powershell -ArgumentList '-NoExit' } | Out-Null
New-ToolButton 'Open CMD'        195 90 { Start-Process cmd } | Out-Null
New-ToolButton 'Extras (3rd-party)' 15 140 {
    $extras = Join-Path $PSScriptRoot 'Extras'
    if (Test-Path $extras) { Start-Process explorer $extras -ErrorAction SilentlyContinue
                             if ($script:IsWinPE) { Start-Process cmd "/k cd /d `"$extras`" && dir" } }
    else { Write-RLog 'No Extras folder found on this drive.' }
} | Out-Null
New-ToolButton 'Save Report'     375 90 {
    $path = Join-Path ([Environment]::GetFolderPath('Desktop')) ("RescueReport_{0:yyyyMMdd_HHmm}.txt" -f (Get-Date))
    if ($script:IsWinPE) { $path = "X:\RescueReport.txt" }
    $txtLog.Text | Set-Content $path
    Write-RLog "Report saved to $path"
} | Out-Null
$btnReboot = New-ToolButton 'Reboot PC' 555 90 {
    if ([System.Windows.Forms.MessageBox]::Show('Reboot now?', 'Rescue', 'YesNo') -eq 'Yes') {
        wpeutil reboot 2>$null; shutdown /r /t 0
    }
}
if (-not $IsWinPE) { $btnReboot.Text = 'Restart Windows' }

$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Text = 'Activity log:'; $lblLog.Location = '15,193'; $lblLog.AutoSize = $true
$form.Controls.AddRange(@($lblMode, $lblLog, $txtLog))

Write-RLog 'Claude Rescue Toolkit ready.'
if ($IsWinPE -and -not $TargetDrive) {
    Write-RLog 'TIP: if the internal drive is BitLocker-encrypted, open CMD and run:'
    Write-RLog '     manage-bde -unlock C: -RecoveryPassword <your-48-digit-key>'
}
[void]$form.ShowDialog()
