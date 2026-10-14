@echo off
rem Double-click launcher for ET Workbench GUI
rem Path is derived from %~dp0 (no hardcoded path, C-2)
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0ETWorkbench\Start-ETWorkbench.ps1"
