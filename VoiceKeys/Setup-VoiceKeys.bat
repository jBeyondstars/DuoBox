@echo off
rem One-time setup for the Vosk engine: Python virtual environment, packages and English model.
title VoiceKeys setup
cd /d "%~dp0"

where py >nul 2>nul && (set PY=py -3) || (set PY=python)

if not exist ".venv\Scripts\python.exe" (
    echo Creating the Python virtual environment...
    %PY% -m venv .venv || goto :error
) else (
    ".venv\Scripts\pip.exe" --version >nul 2>nul
    if errorlevel 1 (
        echo Updating the Python virtual environment paths...
        %PY% -m venv .venv >nul 2>nul
        ".venv\Scripts\python.exe" -c "import pathlib, re; s = pathlib.Path('.venv/Scripts').resolve(); py = b'#!\x22' + str(s / 'python.exe').encode('utf-8') + b'\x22'; [p.write_bytes(re.sub(rb'#!\x22?[^\r\n]+python\.exe\x22?', lambda _: py, p.read_bytes())) for p in s.glob('*.exe')]" >nul 2>nul
        ".venv\Scripts\pip.exe" --version >nul 2>nul
        if errorlevel 1 (
            echo Recreating the Python virtual environment...
            %PY% -m venv --clear .venv || goto :error
        )
    )
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
