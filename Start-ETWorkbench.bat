@echo off
rem Double-click launcher for ET Workbench GUI
rem Path is derived from %~dp0 (no hardcoded path, C-2)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ETWorkbench\Start-ETWorkbench.ps1"
if errorlevel 1 pause
