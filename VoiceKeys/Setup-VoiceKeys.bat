@echo off
rem One-time setup for the Vosk engine: Python virtual environment, packages and English model.
title VoiceKeys setup
cd /d "%~dp0"

where py >nul 2>nul && (set PY=py -3) || (set PY=python)

if not exist ".venv\Scripts\python.exe" (
    echo Creating the Python virtual environment...
    %PY% -m venv .venv || goto :error
)

echo Installing vosk and sounddevice...
".venv\Scripts\python.exe" -m pip install --upgrade --quiet vosk sounddevice || goto :error

if not exist "model\am" (
    echo Downloading the English model vosk-model-small-en-us-0.15 ^(~40 MB^)...
    powershell -NoProfile -Command "$ErrorActionPreference='Stop'; Invoke-WebRequest 'https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip' -OutFile model.zip; Expand-Archive model.zip -DestinationPath . -Force; Remove-Item model.zip; if (Test-Path model) { Remove-Item model -Recurse -Force }; Rename-Item vosk-model-small-en-us-0.15 model" || goto :error
)

".venv\Scripts\python.exe" voicekeys_vosk.py --selftest || goto :error
echo.
echo Setup done. Start VoiceKeys with Start-VoiceKeys-Vosk.bat
pause
exit /b 0

:error
echo.
echo Setup failed.
pause
exit /b 1
