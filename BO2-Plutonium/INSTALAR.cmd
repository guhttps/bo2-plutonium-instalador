@echo off
setlocal
title Instalar Black Ops 2 com Plutonium
if not exist "%~dp0Interface.ps1" (
  echo Extraia todos os arquivos do ZIP antes de executar este instalador.
  pause
  exit /b 1
)
powershell.exe -NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0Interface.ps1"
set "bo2ExitCode=%errorlevel%"
if not "%bo2ExitCode%"=="0" (
  echo Nao foi possivel abrir a janela do instalador.
  pause
)
exit /b %bo2ExitCode%
