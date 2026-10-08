@echo off
rem resolve-file-bridge installer for Windows - double-click or run from a terminal.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
echo.
pause
