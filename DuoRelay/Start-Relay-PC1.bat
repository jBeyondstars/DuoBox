@echo off
rem PC 1 (priest): Ctrl+click in WoW -> PC 2. Ctrl+Alt+D switches the relay ON/OFF.
title DuoRelay PC 1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0DuoRelay.ps1" -Role Sender %*
pause
