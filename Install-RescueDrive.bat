@echo off
:: ===================================================================
::  Claude Rescue Drive — no-exe installer launcher.
::  Use this if dist\RescueDrive.exe is blocked by SmartScreen or
::  quarantined by antivirus. It runs the SAME installer GUI directly
::  from these script files, which security tools don't flag.
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
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "try { Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%~dp0RescueDrive-Installer.ps1\"' } catch { Write-Host $_.Exception.Message; exit 1 }"

if errorlevel 1 (
  echo.
  echo The installer could not be started. If you declined the Administrator
  echo prompt, run this file again and choose Yes.
  echo.
  pause
)
endlocal
