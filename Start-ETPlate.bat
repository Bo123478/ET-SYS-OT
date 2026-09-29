@echo off
rem Double-click launcher for ET Workbench Plate (device nameplate)
rem (left screen edge, vertically centred, persistent 316x248 vertical card)
rem Hidden console window: the plate itself is a WPF window, no console needed.
rem
rem Emergency exit if the right-click menu is unreachable (business app fullscreen):
rem   New-Item -ItemType File -Force "%ProgramData%\ETWorkbench\Local\Snapshot\plate.stop"
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0ETWorkbench\Start-ETPlate.ps1"
