@echo off
title VoiceKeys (Vosk)
cd /d "%~dp0"
if not exist ".venv\Scripts\python.exe" (
    echo Run Setup-VoiceKeys.bat first.
    pause
    exit /b 1
)
".venv\Scripts\python.exe" voicekeys_vosk.py %*
pause
