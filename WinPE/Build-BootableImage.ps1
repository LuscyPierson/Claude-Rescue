<#
.SYNOPSIS
    Builds a bootable WinPE rescue drive with the toolkit baked in.
    Requires the Windows ADK + WinPE add-on. Run elevated.

.PARAMETER DiskNumber
    Physical disk number of the target USB drive. THE DRIVE IS ERASED.
.PARAMETER ToolkitPath
    Path to the Toolkit folder to embed in the image.
.PARAMETER DriversPath
    Optional folder of extracted .inf drivers (storage/network for your hardware)
    to inject into the boot image recursively.
#>
#Requires -RunAsAdministrator
param(
    [Parameter(Mandatory)] [int]    $DiskNumber,
    [Parameter(Mandatory)] [string] $ToolkitPath,
    [string] $DriversPath
)
$ErrorActionPreference = 'Stop'

# Locate the ADK deployment tools.
$adkRoots = @(
    "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit",
    "${env:ProgramFiles}\Windows Kits\10\Assessment and Deployment Kit"
)
$adk = $adkRoots | Where-Object { Test-Path "$_\Windows Preinstallation Environment\copype.cmd" } | Select-Object -First 1
if (-not $adk) { Write-Error 'Windows ADK + WinPE add-on not found. Install both, then retry.'; exit 1 }

$dandi    = "$adk\Deployment Tools\amd64\DISM"
$peRoot   = "$adk\Windows Preinstallation Environment"
$ocsPath  = "$peRoot\amd64\WinPE_OCs"
$work     = Join-Path $env:TEMP "RescuePE_$(Get-Date -Format yyyyMMdd_HHmmss)"
$mount    = Join-Path $work 'mount'

Write-Host "== Creating WinPE working copy in $work"
cmd /c "`"$adk\Deployment Tools\DandISetEnv.bat`" && copype amd64 `"$work\media`"" | Out-Host
if ($LASTEXITCODE) { Write-Error 'copype failed.'; exit 1 }

New-Item -ItemType Directory -Path $mount -Force | Out-Null
$wim = "$work\media\media\sources\boot.wim"

Write-Host '== Mounting boot.wim'
dism /Mount-Image /ImageFile:"$wim" /Index:1 /MountDir:"$mount" | Out-Host

try {
    Write-Host '== Adding PowerShell + WMI + storage support packages'
    # Order matters: each language-neutral package, then its en-us language pack.
    $packages = @(
        'WinPE-WMI', 'WinPE-NetFx', 'WinPE-Scripting', 'WinPE-PowerShell',
        'WinPE-StorageWMI', 'WinPE-DismCmdlets',
        'WinPE-SecureStartup',     # BitLocker (manage-bde) support
        'WinPE-Dot3Svc',           # wired 802.1x network authentication
        'WinPE-FMAPI',             # deleted-file recovery API
        'WinPE-EnhancedStorage',   # eDrive/encrypted-drive hardware support
        'WinPE-WinReCfg'           # Windows RE configuration tooling
    )
    foreach ($p in $packages) {
        dism /Image:"$mount" /Add-Package /PackagePath:"$ocsPath\$p.cab" | Out-Host
        $lang = "$ocsPath\en-us\$p`_en-us.cab"
        if (Test-Path $lang) { dism /Image:"$mount" /Add-Package /PackagePath:"$lang" | Out-Host }
    }

    # More RAM-backed scratch space so scans and tools have room to work.
    dism /Image:"$mount" /Set-ScratchSpace:512 | Out-Host

    if ($DriversPath -and (Test-Path $DriversPath)) {
        Write-Host "== Injecting drivers from $DriversPath"
        dism /Image:"$mount" /Add-Driver /Driver:"$DriversPath" /Recurse | Out-Host
    }

    Write-Host '== Embedding rescue toolkit (including Toolkit\Extras third-party tools)'
    Copy-Item $ToolkitPath "$mount\RescueToolkit" -Recurse -Force

    # Auto-launch the toolkit at boot, with a console left open behind it.
    @"
wpeinit
powershell -NoProfile -ExecutionPolicy Bypass -File X:\RescueToolkit\RescueToolkit.ps1
"@ | Set-Content "$mount\Windows\System32\startnet.cmd" -Encoding Ascii

    Write-Host '== Committing image'
    dism /Unmount-Image /MountDir:"$mount" /Commit | Out-Host
} catch {
    dism /Unmount-Image /MountDir:"$mount" /Discard | Out-Host
    throw
}

Write-Host "== Partitioning and writing USB disk $DiskNumber (ERASING IT)"
# MakeWinPEMedia /UFD needs a drive letter; prepare the disk ourselves so we
# control the layout: single FAT32 boot partition (UEFI + BIOS bootable).
Clear-Disk -Number $DiskNumber -RemoveData -RemoveOEM -Confirm:$false
Initialize-Disk -Number $DiskNumber -PartitionStyle MBR -ErrorAction SilentlyContinue
$part = New-Partition -DiskNumber $DiskNumber -UseMaximumSize -IsActive -AssignDriveLetter
$vol  = Format-Volume -Partition $part -FileSystem FAT32 -NewFileSystemLabel 'RESCUE' -Confirm:$false
$letter = "$($vol.DriveLetter):"

cmd /c "`"$adk\Deployment Tools\DandISetEnv.bat`" && MakeWinPEMedia /UFD /f `"$work\media`" $letter" | Out-Host
if ($LASTEXITCODE) { Write-Error 'MakeWinPEMedia failed.'; exit 1 }

# Also drop the toolkit on the USB root so the same stick works inside Windows.
Copy-Item $ToolkitPath "$letter\RescueToolkit" -Recurse -Force

Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "== DONE. Drive $letter is bootable (boot menu: usually F12/Esc at power-on)."
exit 0
