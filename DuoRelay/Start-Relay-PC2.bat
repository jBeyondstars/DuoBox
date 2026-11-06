@echo off
rem PC 2 (warrior): presses the keys in WoW when PC 1 relays a click.
title DuoRelay PC 2
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0DuoRelay.ps1" -Role Receiver %*
pause
