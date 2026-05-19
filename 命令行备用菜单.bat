@echo off
setlocal EnableExtensions
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0video_downloader.ps1"
if errorlevel 1 (
  echo.
  echo Script exited with an error.
  pause
)
