@echo off
title DuoBox - Hunter combat
cd /d "%~dp0"
if exist ".venv\Scripts\python.exe" (
    ".venv\Scripts\python.exe" combat_monitor.py %*
) else (
    python combat_monitor.py %*
)
pause
