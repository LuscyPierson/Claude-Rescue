@echo off
:: ===================================================================
::  Claude Rescue Drive — one-window app (installer + toolkit).
::  Opens the unified GUI with administrator rights. WinPE runs as
::  SYSTEM already, so it launches directly there.
:: ===================================================================
setlocal
cd /d "%~dp0"

if not exist "%~dp0RescueDrive.ps1" (
  echo ERROR: RescueDrive.ps1 was not found next to this file.
  pause
  exit /b 1
)

reg query "HKLM\SYSTEM\CurrentControlSet\Control\MiniNT" >nul 2>&1
if %errorlevel%==0 (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0RescueDrive.ps1"
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "try { Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','\"%~dp0RescueDrive.ps1\"' } catch { Write-Host $_.Exception.Message; pause }"
)
endlocal
