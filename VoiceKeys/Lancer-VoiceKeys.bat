@echo off
title VoiceKeys
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0VoiceKeys.ps1" %*
pause
