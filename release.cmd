@echo off
REM Один клик: production release = commit + push + GitHub Actions (см. tool/release.ps1)
cd /d "%~dp0"
where powershell >nul 2>&1
if errorlevel 1 (
  echo release.cmd: PowerShell not found
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tool\release.ps1" %*
exit /b %ERRORLEVEL%
