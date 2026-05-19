@echo off
setlocal EnableExtensions
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0make_share_package.ps1"
if errorlevel 1 (
  echo.
  echo Failed to make share package.
  pause
)
