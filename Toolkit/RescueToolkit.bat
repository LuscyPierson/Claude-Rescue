@echo off
:: Launches the rescue toolkit GUI. The .ps1 self-elevates inside full
:: Windows (one UAC prompt) and runs directly in WinPE, so this launcher
:: is a single simple command immune to path-quoting problems.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0RescueToolkit.ps1"
