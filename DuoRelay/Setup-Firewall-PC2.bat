@echo off
rem PC 2, once: firewall rule that lets PC 1's messages in (asks for administrator rights).
title DuoRelay firewall setup
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0DuoRelay.ps1" -SetupFirewall %*
pause
