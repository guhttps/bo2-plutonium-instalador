@echo off
setlocal
title Preparar Plutonium para Black Ops 2
if not exist "%~dp0instalar.ps1" (
  echo Extraia todos os arquivos do ZIP antes de executar este instalador.
  pause
  exit /b 1
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0instalar.ps1"
set "bo2ExitCode=%errorlevel%"
echo.
pause
exit /b %bo2ExitCode%
