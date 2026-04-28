@echo off
REM Вызывает production release.ps1 в корне проекта (сборка перед push, api_keys.json обязателен).
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0release.ps1" %*
exit /b %ERRORLEVEL%
