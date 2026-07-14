@echo off
:: ===================================================================
::  Claude Rescue Drive — no-exe installer launcher.
::  Use this if dist\RescueDrive.exe is blocked by SmartScreen or
::  quarantined by antivirus. The .ps1 self-elevates (one UAC prompt),
::  so this launcher is a single simple command that is immune to
::  quoting problems with spaces in the folder path.
:: ===================================================================
setlocal
cd /d "%~dp0"

if not exist "%~dp0RescueDrive-Installer.ps1" (
  echo.
  echo ERROR: RescueDrive-Installer.ps1 was not found next to this file.
  echo Make sure you extracted the whole folder, not just this .bat.
  echo.
  pause
  exit /b 1
)

echo Launching the Rescue Drive installer (you'll get one Administrator prompt)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0RescueDrive-Installer.ps1"

if errorlevel 1 (
  echo.
  echo The installer could not start. If an error window appeared, see the
  echo details it showed; a copy is saved to %%TEMP%%\RescueDrive-error.log
  echo.
  pause
)
endlocal
