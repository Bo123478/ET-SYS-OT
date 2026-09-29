@echo off
rem Double-click launcher for ET Workbench Tray (left-docked persistent device nameplate)
rem Hidden console window: the badge itself is a WPF window, no console needed.
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0ETWorkbench\Start-ETTray.ps1"
