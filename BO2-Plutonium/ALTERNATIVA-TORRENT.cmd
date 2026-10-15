@echo off
setlocal
title Black Ops 2 - download alternativo por torrent
if not exist "%~dp0instalar.ps1" (
  echo Extraia todos os arquivos do ZIP antes de executar.
  pause
  exit /b 1
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0instalar.ps1" -Torrent
set "bo2ExitCode=%errorlevel%"
echo.
pause
exit /b %bo2ExitCode%
