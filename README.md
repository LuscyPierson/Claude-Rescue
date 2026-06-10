# Claude Rescue Drive

A one-click Windows rescue drive builder. Pick a USB drive, click **Install**, and you get
a drive that works two ways:

1. **Inside Windows** — plug it in and run `RescueToolkit.bat` from the drive.
2. **Outside Windows (bootable)** — boot the PC from the drive into a WinPE recovery
   environment where the same toolkit launches automatically. Useful when the installed
   OS won't start or is too infected to trust.

## What the toolkit does

| Button | What it does |
|---|---|
| **Malware Scan** | Runs Windows Defender (quick/full/custom path). In boot mode it scans the offline Windows installation. |
| **Registry Check** | Audits autorun keys (Run/RunOnce), Winlogon shell/userinit hijacks, Image File Execution Options debuggers, and suspicious services. Loads offline hives when booted from the drive. |
| **Diagnostics** | SMART disk health, `sfc /scannow`, `DISM ScanHealth`, battery report, RAM test scheduling, and recent critical errors from the event log. |
| **Temp Cleanup** | Clears user/system temp folders, Windows Update download cache, and recycle bin; reports space freed. |
| **PowerShell / CMD** | Opens an elevated console for manual work. |

## Quick start

On a Windows 10/11 machine (as Administrator):

```
Install-RescueDrive.bat
```

1. Pick your USB drive from the list.
2. Choose **Toolkit only** (no formatting, just copies files) or **Full bootable drive**
   (erases the drive, builds WinPE, makes it bootable).
3. Click **Install** and wait.

### Requirements for the bootable option

The bootable build uses Microsoft's official preinstallation environment (WinPE),
which requires two free Microsoft installers on the build machine:

- [Windows ADK](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install)
- The **WinPE add-on** for the ADK (same page)

The installer GUI detects whether they're present and tells you if not.
**Toolkit only** mode has no requirements beyond Windows + PowerShell 5.1.

## Repo layout

```
Install-RescueDrive.bat        Elevating launcher for the installer GUI
RescueDrive-Installer.ps1      GUI: pick a drive, install/build
Toolkit/
  RescueToolkit.bat            Elevating launcher for the toolkit GUI
  RescueToolkit.ps1            Toolkit GUI (works in Windows and WinPE)
  Modules/
    MalwareScan.ps1
    RegistryCheck.ps1
    Diagnostics.ps1
    TempCleanup.ps1
WinPE/
  Build-BootableImage.ps1      Builds WinPE with the toolkit baked in, writes it to USB
```

## Notes & limitations

- Booting from USB requires enabling it in the PC's firmware (BIOS/UEFI) boot menu,
  usually F12/F2/Esc/Del at power-on. Secure Boot is fine — WinPE is Microsoft-signed.
- In boot (WinPE) mode, Defender real-time engine isn't available; the toolkit uses the
  offline Windows installation's Defender platform when present, and always supports
  registry/diagnostic/cleanup operations against the offline OS.
- BitLocker-encrypted drives must be unlocked first (`manage-bde -unlock C: -RecoveryPassword <key>`),
  the toolkit's console buttons make that easy.
