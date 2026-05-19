@echo off
title Multi-Platform Video Downloader Setup

echo ============================================
echo  Multi-Platform Video Downloader - Setup
echo ============================================
echo.
echo This script will download all runtime dependencies:
echo   - yt-dlp, FFmpeg, Deno, uv, douyin-backend
echo.
echo First-time download may take a few minutes.
echo.
pause

echo.
echo [1/2] Running portable update tool...
powershell -ExecutionPolicy Bypass -File "%~dp0portable_update_tools.ps1"
if %errorlevel% neq 0 (
    echo.
echo [!] Setup failed. Check the log above for details.
    pause
    exit /b 1
)

echo.
echo [2/2] Setup complete!
echo.
echo You can now run:
echo   video_downloader_gui.ps1    - Graphical interface
echo.
pause
