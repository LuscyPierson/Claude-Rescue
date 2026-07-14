@echo off
:: ===================================================================
::  Claude Rescue Drive — one-window app (installer + toolkit).
::  The .ps1 self-elevates (one UAC prompt), so this launcher is a
::  single simple command that is immune to quoting problems with
::  spaces in the folder path. WinPE runs it directly as SYSTEM.
:: ===================================================================
setlocal
cd /d "%~dp0"

if not exist "%~dp0RescueDrive.ps1" (
  echo ERROR: RescueDrive.ps1 was not found next to this file.
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0RescueDrive.ps1"

if errorlevel 1 (
  echo.
  echo The app could not start. If an error window appeared, see the
  echo details it showed; a copy is saved to %%TEMP%%\RescueDrive-error.log
  echo.
  pause
)
endlocal
