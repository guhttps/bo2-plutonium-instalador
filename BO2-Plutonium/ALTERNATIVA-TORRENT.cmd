@echo off
setlocal
title Black Ops 2 - download alternativo por torrent
if not exist "%~dp0Interface.ps1" (
  echo Extraia todos os arquivos do ZIP antes de executar.
  pause
  exit /b 1
)
powershell.exe -NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0Interface.ps1" -Torrent
set "bo2ExitCode=%errorlevel%"
if not "%bo2ExitCode%"=="0" (
  echo Nao foi possivel abrir a janela do instalador.
  pause
)
exit /b %bo2ExitCode%
