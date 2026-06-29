<#
.SYNOPSIS
    Claude Rescue Drive — unified GUI.
    One window that does everything: create a rescue USB (toolkit-only or full
    bootable WinPE) AND run the rescue toolkit (malware scan, registry audit,
    diagnostics, temp cleanup, consoles, report). Works inside Windows and,
    when booted from the drive, inside WinPE against the offline installation.

    Launch elevated via Start-RescueDrive.bat (or RescueDrive.exe).
#>
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

trap {
    [System.Windows.Forms.MessageBox]::Show(
        "Claude Rescue Drive could not start:`n`n$($_.Exception.Message)",
        'Claude Rescue Drive', 'OK', 'Error') | Out-Null
    exit 1
}
$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------------- context ---
$RepoRoot   = $PSScriptRoot
$ToolkitDir = if (Test-Path (Join-Path $RepoRoot 'Toolkit')) { Join-Path $RepoRoot 'Toolkit' } else { $RepoRoot }
$ModulesDir = if (Test-Path (Join-Path $ToolkitDir 'Modules')) { Join-Path $ToolkitDir 'Modules' } else { Join-Path $RepoRoot 'Modules' }
$BuildScript = Join-Path $RepoRoot 'WinPE\Build-BootableImage.ps1'

$script:IsWinPE = Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT'

function Find-OfflineWindows {
    foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
        if ($d.DriveType -ne 'Fixed' -or -not $d.IsReady) { continue }
        if ($d.Name -like 'X:*') { continue }
        if (Test-Path (Join-Path $d.Name 'Windows\System32\config\SOFTWARE')) { return $d.Name.TrimEnd('\') }
    }
    return $null
}
$script:TargetDrive = if ($script:IsWinPE) { Find-OfflineWindows } else { $env:SystemDrive }

# Load the toolkit feature modules (Invoke-MalwareScan, -RegistryCheck, etc.).
if (Test-Path $ModulesDir) {
    foreach ($m in Get-ChildItem $ModulesDir -Filter *.ps1) { . $m.FullName }
}

# ------------------------------------------------------------------ colors ---
$cBg      = [System.Drawing.Color]::FromArgb(243,243,243)
$cSide    = [System.Drawing.Color]::FromArgb(32,38,54)
$cSideSel = [System.Drawing.Color]::FromArgb(0,120,212)
$cSideTxt = [System.Drawing.Color]::FromArgb(210,216,228)
$cCard    = [System.Drawing.Color]::White
$cAccent  = [System.Drawing.Color]::FromArgb(0,120,212)
$cText    = [System.Drawing.Color]::FromArgb(28,28,28)
$cLogBg   = [System.Drawing.Color]::FromArgb(24,24,24)
$cLogTxt  = [System.Drawing.Color]::FromArgb(210,230,210)
$fUI      = New-Object System.Drawing.Font('Segoe UI', 9)
$fHead    = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
$fSub     = New-Object System.Drawing.Font('Segoe UI', 9)
$fNav     = New-Object System.Drawing.Font('Segoe UI', 9.5)

# -------------------------------------------------------------------- form ---
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Claude Rescue Drive' + $(if ($script:IsWinPE) { '  [BOOT MODE]' } else { '' })
$form.Size = New-Object System.Drawing.Size(940, 620)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $cBg
$form.Font = $fUI

# NOTE on docking: WinForms docks controls in REVERSE order of the Controls
# collection (last added is docked first). So Fill controls are added FIRST
# (docked last → take the leftover space) and edge controls are added after.

# Content area (Fill) — added before the sidebar so it takes the leftover area.
$content = New-Object System.Windows.Forms.Panel
$content.Dock = 'Fill'; $content.BackColor = $cBg; $content.Padding = '28,20,28,20'
$form.Controls.Add($content)

# Sidebar (Left) ------------------------------------------------------------
$sidebar = New-Object System.Windows.Forms.Panel
$sidebar.Dock = 'Left'; $sidebar.Width = 224; $sidebar.BackColor = $cSide
$form.Controls.Add($sidebar)

# Drawn app logo: a blue disc with a white rescue cross (GDI+, no image file).
$logoPanel = New-Object System.Windows.Forms.Panel
$logoPanel.Location = '20,20'; $logoPanel.Size = '48,48'; $logoPanel.BackColor = $cSide
$logoPanel.Add_Paint({
    param($s, $e)
    $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'
    $disc = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Rectangle(0, 0, 46, 46)),
        [System.Drawing.Color]::FromArgb(0, 153, 255),
        [System.Drawing.Color]::FromArgb(0, 90, 180), 90.0)
    $g.FillEllipse($disc, 1, 1, 44, 44)
    $white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
    $g.FillRectangle($white, 20, 11, 6, 24)   # vertical bar of the cross
    $g.FillRectangle($white, 11, 20, 24, 6)   # horizontal bar of the cross
    $disc.Dispose(); $white.Dispose()
})
$sidebar.Controls.Add($logoPanel)

$logo = New-Object System.Windows.Forms.Label
$logo.Text = "Claude`r`nRescue Drive"; $logo.ForeColor = [System.Drawing.Color]::White
$logo.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
$logo.Location = '76,18'; $logo.Size = '140,44'
$sidebar.Controls.Add($logo)

$lblMode = New-Object System.Windows.Forms.Label
$lblMode.Location = '20,540'; $lblMode.Size = '190,40'
$lblMode.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$lblMode.ForeColor = if ($script:IsWinPE) { [System.Drawing.Color]::Orange } else { [System.Drawing.Color]::FromArgb(120,200,140) }
$lblMode.Text = if ($script:IsWinPE) {
    if ($script:TargetDrive) { "BOOT MODE`nRepairing offline $($script:TargetDrive)" } else { "BOOT MODE`nNo Windows found (BitLocker?)" }
} else { "Running inside Windows`n($($script:TargetDrive))" }
$sidebar.Controls.Add($lblMode)

# Inside $content: panel host (Fill) added first, log strip (Bottom) added after.
$host_ = New-Object System.Windows.Forms.Panel
$host_.Dock = 'Fill'; $host_.BackColor = $cBg
$content.Controls.Add($host_)

$logPanel = New-Object System.Windows.Forms.Panel
$logPanel.Dock = 'Bottom'; $logPanel.Height = 150; $logPanel.BackColor = $cBg
$content.Controls.Add($logPanel)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Dock = 'Fill'; $txtLog.Multiline = $true
$txtLog.ReadOnly = $true; $txtLog.ScrollBars = 'Vertical'
$txtLog.BackColor = $cLogBg; $txtLog.ForeColor = $cLogTxt
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 9); $txtLog.BorderStyle = 'None'
$logPanel.Controls.Add($txtLog)
$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Text = 'Activity log'; $lblLog.Dock = 'Top'; $lblLog.Height = 20
$lblLog.ForeColor = [System.Drawing.Color]::Gray
$logPanel.Controls.Add($lblLog)

function Write-RLog([string]$msg) {
    $txtLog.AppendText(("[{0:HH:mm:ss}] {1}`r`n" -f (Get-Date), $msg))
    [System.Windows.Forms.Application]::DoEvents()
}

# ------------------------------------------------------- panel construction --
$script:panels = @{}
function New-Panel([string]$key, [string]$title, [string]$sub, [int]$glyph = 0) {
    $p = New-Object System.Windows.Forms.Panel
    $p.Dock = 'Fill'; $p.BackColor = $cBg; $p.Visible = $false
    $off = 0
    if ($glyph) {
        $gi = New-Object System.Windows.Forms.Label
        $gi.Text = [char]$glyph; $gi.Font = New-Object System.Drawing.Font('Segoe MDL2 Assets', 22)
        $gi.ForeColor = $cAccent; $gi.Location = '0,4'; $gi.Size = '40,40'; $gi.TextAlign = 'MiddleCenter'
        $p.Controls.Add($gi); $off = 48
    }
    $h = New-Object System.Windows.Forms.Label
    $h.Text = $title; $h.Font = $fHead; $h.ForeColor = $cText; $h.Location = "$off,8"; $h.AutoSize = $true
    $s = New-Object System.Windows.Forms.Label
    $s.Text = $sub; $s.Font = $fSub; $s.ForeColor = [System.Drawing.Color]::Gray; $s.Location = "$([int]($off + 2)),42"; $s.AutoSize = $true
    $p.Controls.AddRange(@($h, $s))
    $host_.Controls.Add($p)
    $script:panels[$key] = $p
    $p
}
function New-Btn($parent, [string]$text, [int]$x, [int]$y, [int]$w, [scriptblock]$onClick, [bool]$primary = $true) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text; $b.Location = "$x,$y"; $b.Size = "$w,34"; $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = $(if ($primary) { 0 } else { 1 })
    $b.BackColor = $(if ($primary) { $cAccent } else { $cCard })
    $b.ForeColor = $(if ($primary) { [System.Drawing.Color]::White } else { $cText })
    $b.Font = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold)
    $b.Add_Click({ $this.Enabled = $false; try { & $onClick } catch { Write-RLog "ERROR: $($_.Exception.Message)" } finally { $this.Enabled = $true } }.GetNewClosure())
    $parent.Controls.Add($b); $b
}
function Show-Panel([string]$key) {
    foreach ($k in $script:panels.Keys) { $script:panels[$k].Visible = ($k -eq $key) }
    foreach ($n in $script:nav) {
        $sel = ($n.Tag -eq $key)
        $n.BackColor = $(if ($sel) { $cSideSel } else { $cSide })
        foreach ($c in $n.Controls) { $c.ForeColor = $(if ($sel) { [System.Drawing.Color]::White } else { $cSideTxt }) }
    }
}

# ------------------------------------------------------------- nav rows ------
# Each row is an icon (Segoe MDL2 Assets glyph) + label, the whole row clickable.
$script:nav = @()
$fIcon = New-Object System.Drawing.Font('Segoe MDL2 Assets', 12)
$navItems = @(
    @('home',     'Home',                0xE80F),   # Home
    @('create',   'Create Rescue Drive', 0xE88E),   # Save (write to drive)
    @('malware',  'Malware Scan',        0xEA18),   # Shield
    @('registry', 'Registry Check',      0xE721),   # Search
    @('diag',     'Diagnostics',         0xE713),   # Settings (gear)
    @('cleanup',  'Temp Cleanup',        0xE74D),   # Delete
    @('console',  'Open Console',        0xE756),   # CommandPrompt
    @('report',   'Save Report',         0xE896)    # Download
)
$ny = 96
foreach ($it in $navItems) {
    $row = New-Object System.Windows.Forms.Panel
    $row.Location = "10,$ny"; $row.Size = '204,36'; $row.BackColor = $cSide; $row.Tag = $it[0]; $row.Cursor = 'Hand'
    $ic = New-Object System.Windows.Forms.Label
    $ic.Text = [char]$it[2]; $ic.Font = $fIcon; $ic.ForeColor = $cSideTxt; $ic.BackColor = 'Transparent'
    $ic.Location = '12,7'; $ic.Size = '24,22'; $ic.TextAlign = 'MiddleCenter'
    $tx = New-Object System.Windows.Forms.Label
    $tx.Text = $it[1]; $tx.Font = $fNav; $tx.ForeColor = $cSideTxt; $tx.BackColor = 'Transparent'
    $tx.Location = '44,9'; $tx.Size = '150,20'
    $row.Controls.AddRange(@($ic, $tx))
    $click = { Show-Panel $row.Tag }.GetNewClosure()
    $row.Add_Click($click); $ic.Add_Click($click); $tx.Add_Click($click)
    $sidebar.Controls.Add($row); $script:nav += $row
    $ny += 42
}

# ===================================================== PANEL: Home ============
$pHome = New-Panel 'home' 'Welcome' 'Pick a task on the left, or start with one of these.' 0xE80F
New-Btn $pHome 'Create a rescue USB drive' 0 90 260 { Show-Panel 'create' } $true | Out-Null
New-Btn $pHome 'Scan this PC for malware'  0 134 260 { Show-Panel 'malware' } $false | Out-Null
New-Btn $pHome 'Run full diagnostics'      0 178 260 { Show-Panel 'diag' } $false | Out-Null
$hi = New-Object System.Windows.Forms.Label
$hi.Location = '280,92'; $hi.Size = '330,140'; $hi.Font = $fUI; $hi.ForeColor = [System.Drawing.Color]::DimGray
$hi.Text = "This drive works two ways:`r`n`r`n• Inside Windows — run tools on the live PC.`r`n• Booted from USB — repair a PC that won't start.`r`n`r`nEverything you do is recorded in the Activity log below; use Save Report to keep a copy."
$pHome.Controls.Add($hi)

# ============================================== PANEL: Create Rescue Drive ====
$pCreate = New-Panel 'create' 'Create Rescue Drive' 'Turn a USB stick into a bootable Windows rescue & repair drive.' 0xE88E
$lblPick = New-Object System.Windows.Forms.Label
$lblPick.Text = '1.  Select USB drive'; $lblPick.Location = '0,84'; $lblPick.AutoSize = $true
$lblPick.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$listDrives = New-Object System.Windows.Forms.ListBox
$listDrives.Location = '0,110'; $listDrives.Size = '560,70'
$pCreate.Controls.AddRange(@($lblPick, $listDrives))
New-Btn $pCreate 'Refresh' 470 186 90 { Refresh-Drives } $false | Out-Null

$lblMode2 = New-Object System.Windows.Forms.Label
$lblMode2.Text = '2.  Choose install mode'; $lblMode2.Location = '0,228'; $lblMode2.AutoSize = $true
$lblMode2.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$radToolkit = New-Object System.Windows.Forms.RadioButton
$radToolkit.Text = 'Toolkit only — copy the rescue tools onto the drive (keeps existing files)'
$radToolkit.Location = '4,256'; $radToolkit.Size = '560,20'; $radToolkit.Checked = $true
$radBootable = New-Object System.Windows.Forms.RadioButton
$radBootable.Text = 'Full bootable rescue drive — ERASES the drive, builds WinPE (needs Windows ADK)'
$radBootable.Location = '4,282'; $radBootable.Size = '560,20'
$lblAdk = New-Object System.Windows.Forms.Label
$lblAdk.Location = '4,308'; $lblAdk.Size = '560,18'
$pCreate.Controls.AddRange(@($lblMode2, $radToolkit, $radBootable, $lblAdk))
New-Btn $pCreate 'Install' 0 340 150 { Do-Install } $true | Out-Null

function Test-AdkInstalled {
    foreach ($r in @("${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit",
                     "${env:ProgramFiles}\Windows Kits\10\Assessment and Deployment Kit")) {
        if (Test-Path (Join-Path $r 'Windows Preinstallation Environment\copype.cmd')) { return $r }
    }
    return $null
}
function Get-UsbDisks {
    try {
        Get-Disk -ErrorAction Stop | Where-Object { $_.BusType -eq 'USB' } | ForEach-Object {
            $disk = $_
            $letters = (Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue |
                Where-Object DriveLetter | ForEach-Object { "$($_.DriveLetter):" }) -join ' '
            [pscustomobject]@{
                Number  = $disk.Number
                Label   = '{0} — {1} ({2:N1} GB) {3}' -f $disk.Number, $disk.FriendlyName, ($disk.Size/1GB),
                          $(if ($letters) { "[$letters]" } else { '[no letter]' })
                Letters = $letters
            }
        }
    } catch { Write-RLog "Could not list drives: $($_.Exception.Message)" }
}
$script:disks = @()
function Refresh-Drives {
    $listDrives.Items.Clear()
    $script:disks = @(Get-UsbDisks)
    foreach ($d in $script:disks) { [void]$listDrives.Items.Add($d.Label) }
    if (-not $script:disks) { [void]$listDrives.Items.Add('(no USB drives detected — plug one in and click Refresh)') }
}
function Do-Install {
    if ($listDrives.SelectedIndex -lt 0 -or -not $script:disks) {
        [System.Windows.Forms.MessageBox]::Show('Select a USB drive first.', 'Rescue Drive') | Out-Null; return
    }
    $disk = $script:disks[$listDrives.SelectedIndex]
    if ($radToolkit.Checked) {
        $letter = ($disk.Letters -split ' ')[0]
        if (-not $letter) { throw 'Selected drive has no drive letter. Format it first or use bootable mode.' }
        $dest = Join-Path "$letter\" 'RescueToolkit'
        Write-RLog "Copying toolkit to $dest ..."
        Copy-Item $ToolkitDir $dest -Recurse -Force
        Write-RLog "Done. Run $dest\RescueToolkit.bat on any Windows PC."
    } else {
        if ([System.Windows.Forms.MessageBox]::Show(
            "This ERASES everything on disk $($disk.Number).`n`nContinue?", 'Confirm erase', 'YesNo', 'Warning') -ne 'Yes') {
            Write-RLog 'Cancelled.'; return
        }
        Write-RLog 'Building bootable WinPE rescue drive (10-30 min, watch the console)...'
        $a = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$BuildScript`"",'-DiskNumber',$disk.Number,'-ToolkitPath',"`"$ToolkitDir`"")
        $p = Start-Process powershell -Verb RunAs -Wait -PassThru -ArgumentList $a
        if ($p.ExitCode -eq 0) { Write-RLog 'Bootable rescue drive created successfully.' } else { Write-RLog "Build FAILED (exit $($p.ExitCode))." }
    }
    Refresh-Drives
}

# Helper to build a simple "buttons + this panel shares the log" tool panel.
function Add-ToolButtons($panel, $buttons) {
    $x = 0
    foreach ($b in $buttons) {
        New-Btn $panel $b.Text $x 90 $b.Width $b.Action $b.Primary | Out-Null
        $x += $b.Width + 12
    }
}

# ===================================================== PANEL: Malware =========
$pMal = New-Panel 'malware' 'Malware Scan' 'Scan with Windows Defender. In boot mode this scans the offline Windows.' 0xEA18
Add-ToolButtons $pMal @(
    @{ Text='Quick scan';  Width=150; Primary=$true;  Action={ $script:scanType=1; Invoke-MalwareScan -Target $script:TargetDrive -IsWinPE $script:IsWinPE } },
    @{ Text='Full scan';   Width=150; Primary=$false; Action={ $script:scanType=2; Invoke-MalwareScan -Target $script:TargetDrive -IsWinPE $script:IsWinPE } }
)

# ===================================================== PANEL: Registry ========
$pReg = New-Panel 'registry' 'Registry Check' 'Audit autoruns, logon hijacks, IFEO debuggers, and suspicious services.' 0xE721
Add-ToolButtons $pReg @(
    @{ Text='Run registry audit'; Width=190; Primary=$true; Action={ Invoke-RegistryCheck -Target $script:TargetDrive -IsWinPE $script:IsWinPE } }
)

# ===================================================== PANEL: Diagnostics =====
$pDiag = New-Panel 'diag' 'Diagnostics' 'Disk health, system file integrity, and recent critical errors.' 0xE713
Add-ToolButtons $pDiag @(
    @{ Text='Run full diagnostics'; Width=190; Primary=$true; Action={ Invoke-Diagnostics -Target $script:TargetDrive -IsWinPE $script:IsWinPE } }
)

# ===================================================== PANEL: Cleanup =========
$pClean = New-Panel 'cleanup' 'Temp Cleanup' 'Clear temp folders, Windows Update cache, and the recycle bin.' 0xE74D
Add-ToolButtons $pClean @(
    @{ Text='Clean temporary files'; Width=200; Primary=$true; Action={ Invoke-TempCleanup -Target $script:TargetDrive -IsWinPE $script:IsWinPE } }
)

# ===================================================== PANEL: Console =========
$pCon = New-Panel 'console' 'Open Console' 'Open an elevated console for manual work.' 0xE756
Add-ToolButtons $pCon @(
    @{ Text='Open PowerShell'; Width=160; Primary=$true;  Action={ Start-Process powershell -ArgumentList '-NoExit'; Write-RLog 'Opened PowerShell.' } },
    @{ Text='Open CMD';        Width=160; Primary=$false; Action={ Start-Process cmd; Write-RLog 'Opened CMD.' } }
)

# ===================================================== PANEL: Report ==========
$pRep = New-Panel 'report' 'Save Report' 'Save everything in the activity log to a text file.' 0xE896
Add-ToolButtons $pRep @(
    @{ Text='Save report'; Width=160; Primary=$true; Action={
        $path = if ($script:IsWinPE) { 'X:\RescueReport.txt' }
                else { Join-Path ([Environment]::GetFolderPath('Desktop')) ("RescueReport_{0:yyyyMMdd_HHmm}.txt" -f (Get-Date)) }
        $txtLog.Text | Set-Content $path; Write-RLog "Report saved to $path" } }
)

# ------------------------------------------------------------------ startup ---
Refresh-Drives
$script:adkRoot = Test-AdkInstalled
if ($script:adkRoot) { $lblAdk.Text = 'Windows ADK + WinPE add-on: detected.'; $lblAdk.ForeColor = [System.Drawing.Color]::DarkGreen }
else { $lblAdk.Text = 'Windows ADK not found — bootable mode disabled (see README).'; $lblAdk.ForeColor = [System.Drawing.Color]::Firebrick; $radBootable.Enabled = $false }

Show-Panel 'home'
Write-RLog 'Claude Rescue Toolkit ready.'
if ($script:IsWinPE -and -not $script:TargetDrive) {
    Write-RLog 'TIP: if the internal drive is BitLocker-encrypted, open a console and run:'
    Write-RLog '     manage-bde -unlock C: -RecoveryPassword <your-48-digit-key>'
}
[void]$form.ShowDialog()
