@echo off
:: Launches the rescue toolkit GUI. Elevates when running inside full Windows;
:: WinPE is always SYSTEM so it just runs directly there.
cd /d "%~dp0"
reg query "HKLM\SYSTEM\CurrentControlSet\Control\MiniNT" >nul 2>&1
if %errorlevel%==0 (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0RescueToolkit.ps1"
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','\"%~dp0RescueToolkit.ps1\"'"
)
