@echo off
setlocal
title Instalar Black Ops 2 com Plutonium
for %%F in (Interface.ps1 instalar.ps1 Funcoes.ps1 Progresso.ps1 componentes.ps1 TorrentVerifier.cs arquivos-http.json pluto_t6_full_game.torrent) do (
  if not exist "%~dp0%%F" (
    set "bo2MissingFile=%%F"
    goto pacote_incompleto
  )
)
powershell.exe -NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0Interface.ps1"
set "bo2ExitCode=%errorlevel%"
if not "%bo2ExitCode%"=="0" (
  echo Nao foi possivel abrir a janela do instalador.
  pause
)
exit /b %bo2ExitCode%

:pacote_incompleto
echo O pacote esta incompleto. Falta o arquivo: %bo2MissingFile%
echo.
echo Feche esta janela. Clique com o botao direito em BO2-Plutonium.zip
echo e escolha "Extrair Tudo...". Depois, abra INSTALAR.cmd na pasta extraida,
echo fora do ZIP. Nao abra o instalador de dentro do arquivo compactado.
echo Se ja extraiu tudo, baixe novamente o ZIP completo e extraia em uma nova pasta.
echo.
pause
exit /b 1
