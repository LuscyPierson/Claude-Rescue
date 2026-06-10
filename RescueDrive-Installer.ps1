<#
.SYNOPSIS
    Claude Rescue Drive installer GUI.
    Lists USB drives, lets the user pick one, and either copies the toolkit onto it
    or builds a full bootable WinPE rescue drive.
#>
#Requires -RunAsAdministrator
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'
$RepoRoot = $PSScriptRoot
$ToolkitDir = Join-Path $RepoRoot 'Toolkit'
$BuildScript = Join-Path $RepoRoot 'WinPE\Build-BootableImage.ps1'

function Get-UsbDisks {
    Get-Disk | Where-Object { $_.BusType -eq 'USB' } | ForEach-Object {
        $disk = $_
        $letters = (Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue |
            Where-Object DriveLetter | ForEach-Object { "$($_.DriveLetter):" }) -join ' '
        [pscustomobject]@{
            Number  = $disk.Number
            Label   = '{0} — {1} ({2:N1} GB) {3}' -f $disk.Number, $disk.FriendlyName,
                       ($disk.Size / 1GB), $(if ($letters) { "[$letters]" } else { '[no letter]' })
            Letters = $letters
        }
    }
}

function Test-AdkInstalled {
    $roots = @(
        "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit",
        "${env:ProgramFiles}\Windows Kits\10\Assessment and Deployment Kit"
    )
    foreach ($r in $roots) {
        if (Test-Path (Join-Path $r 'Windows Preinstallation Environment\copype.cmd')) { return $r }
    }
    return $null
}

# ---------------------------------------------------------------- UI ----------
$form              = New-Object System.Windows.Forms.Form
$form.Text         = 'Claude Rescue Drive — Installer'
$form.Size         = New-Object System.Drawing.Size(560, 470)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox  = $false

$lblDrives         = New-Object System.Windows.Forms.Label
$lblDrives.Text    = 'Select the USB drive to install onto:'
$lblDrives.Location = '15,15'
$lblDrives.AutoSize = $true

$listDrives        = New-Object System.Windows.Forms.ListBox
$listDrives.Location = '15,40'
$listDrives.Size   = '515,90'

$btnRefresh        = New-Object System.Windows.Forms.Button
$btnRefresh.Text   = 'Refresh drives'
$btnRefresh.Location = '15,135'
$btnRefresh.Size   = '120,28'

$grpMode           = New-Object System.Windows.Forms.GroupBox
$grpMode.Text      = 'Install mode'
$grpMode.Location  = '15,175'
$grpMode.Size      = '515,105'

$radToolkit        = New-Object System.Windows.Forms.RadioButton
$radToolkit.Text   = 'Toolkit only — copy the rescue tools onto the drive (keeps existing files)'
$radToolkit.Location = '12,22'
$radToolkit.Size   = '490,20'
$radToolkit.Checked = $true

$radBootable       = New-Object System.Windows.Forms.RadioButton
$radBootable.Text  = 'Full bootable rescue drive — ERASES the drive, builds WinPE (needs Windows ADK)'
$radBootable.Location = '12,48'
$radBootable.Size  = '490,20'

$lblAdk            = New-Object System.Windows.Forms.Label
$lblAdk.Location   = '12,74'
$lblAdk.Size       = '490,20'
$grpMode.Controls.AddRange(@($radToolkit, $radBootable, $lblAdk))

$txtLog            = New-Object System.Windows.Forms.TextBox
$txtLog.Location   = '15,290'
$txtLog.Size       = '515,95'
$txtLog.Multiline  = $true
$txtLog.ReadOnly   = $true
$txtLog.ScrollBars = 'Vertical'

$btnInstall        = New-Object System.Windows.Forms.Button
$btnInstall.Text   = 'Install'
$btnInstall.Location = '400,395'
$btnInstall.Size   = '130,32'
$btnInstall.Font   = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)

$form.Controls.AddRange(@($lblDrives, $listDrives, $btnRefresh, $grpMode, $txtLog, $btnInstall))

$script:disks = @()
function Write-Log([string]$msg) {
    $txtLog.AppendText(("[{0:HH:mm:ss}] {1}`r`n" -f (Get-Date), $msg))
    [System.Windows.Forms.Application]::DoEvents()
}
function Refresh-Drives {
    $listDrives.Items.Clear()
    $script:disks = @(Get-UsbDisks)
    foreach ($d in $script:disks) { [void]$listDrives.Items.Add($d.Label) }
    if (-not $script:disks) { [void]$listDrives.Items.Add('(no USB drives detected — plug one in and click Refresh)') }
}
$btnRefresh.Add_Click({ Refresh-Drives })

$script:adkRoot = Test-AdkInstalled
if ($script:adkRoot) {
    $lblAdk.Text = 'Windows ADK + WinPE add-on: detected.'
    $lblAdk.ForeColor = 'DarkGreen'
} else {
    $lblAdk.Text = 'Windows ADK + WinPE add-on not found — bootable mode disabled (see README).'
    $lblAdk.ForeColor = 'Firebrick'
    $radBootable.Enabled = $false
}

function Install-ToolkitOnly($disk) {
    $letter = ($disk.Letters -split ' ')[0]
    if (-not $letter) { throw 'Selected drive has no drive letter. Format it first or use bootable mode.' }
    $dest = Join-Path "$letter\" 'RescueToolkit'
    Write-Log "Copying toolkit to $dest ..."
    Copy-Item $ToolkitDir $dest -Recurse -Force
    Write-Log "Done. Run $dest\RescueToolkit.bat on any Windows PC."
}

function Install-Bootable($disk) {
    $res = [System.Windows.Forms.MessageBox]::Show(
        "This will ERASE everything on disk $($disk.Number) ($($disk.Label)).`n`nContinue?",
        'Confirm erase', 'YesNo', 'Warning')
    if ($res -ne 'Yes') { Write-Log 'Cancelled.'; return }
    Write-Log 'Building bootable WinPE rescue drive (10-30 minutes, watch the console window)...'
    $buildArgs = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$BuildScript`"",
        '-DiskNumber', $disk.Number, '-ToolkitPath', "`"$ToolkitDir`"")
    $driversDir = Join-Path $RepoRoot 'Drivers'
    if (Test-Path $driversDir) {
        Write-Log "Found Drivers folder — drivers will be injected into the boot image."
        $buildArgs += @('-DriversPath', "`"$driversDir`"")
    }
    $p = Start-Process powershell -Verb RunAs -Wait -PassThru -ArgumentList $buildArgs
    if ($p.ExitCode -eq 0) { Write-Log 'Bootable rescue drive created successfully.' }
    else { Write-Log "Build FAILED (exit code $($p.ExitCode)). See console output." }
}

$btnInstall.Add_Click({
    try {
        if ($listDrives.SelectedIndex -lt 0 -or -not $script:disks) {
            [System.Windows.Forms.MessageBox]::Show('Select a USB drive first.', 'Rescue Drive') | Out-Null
            return
        }
        $disk = $script:disks[$listDrives.SelectedIndex]
        $btnInstall.Enabled = $false
        if ($radToolkit.Checked) { Install-ToolkitOnly $disk } else { Install-Bootable $disk }
        Refresh-Drives
    } catch {
        Write-Log "ERROR: $($_.Exception.Message)"
    } finally {
        $btnInstall.Enabled = $true
    }
})

Refresh-Drives
[void]$form.ShowDialog()
