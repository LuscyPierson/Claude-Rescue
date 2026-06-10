@echo off
:: Launches the rescue drive installer GUI with admin rights.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','\"%~dp0RescueDrive-Installer.ps1\"'"
