[CmdletBinding()]
param([switch]$Download, [string]$CachePath=(Join-Path $env:LOCALAPPDATA 'BO2-Plutonium-Assistente\cache'), [string]$PreviewPath,
    [string]$PackagePath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $PackagePath) { $PackagePath = Join-Path $PSScriptRoot 'BO2-Plutonium' }
. (Join-Path $packagePath 'Funcoes.ps1')
. (Join-Path $packagePath 'Progresso.ps1')
$active = @(
    [pscustomobject]@{gid='a';status='active';totalLength='100';completedLength='100'},
    [pscustomobject]@{gid='b';status='active';totalLength='200';completedLength='40'}
)
$stopped = @(
    [pscustomobject]@{gid='a';status='complete';totalLength='100';completedLength='100'},
    [pscustomobject]@{gid='c';status='error';totalLength='500';completedLength='500'}
)
$progress = Measure-DownloadProgress -Active $active -Stopped $stopped -TotalBytes 1000 -TotalFiles 3
if ($progress.CompletedBytes -ne 140 -or $progress.Percent -ne 14 -or $progress.CompletedFiles -ne 1) { throw 'O total contou um arquivo duas vezes ou aceitou uma transferencia com erro.' }
$zero = Measure-DownloadProgress -Active @() -Stopped @() -TotalBytes 0 -TotalFiles 0
if ($zero.Percent -ne 0) { throw 'Progresso invalido sem arquivos.' }
Write-Host 'OK: progresso total por bytes, arquivos de tamanhos diferentes e exclusao de erros/duplicatas.'

$testPath = Join-Path $PSScriptRoot ('.verificacao-interface-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testPath | Out-Null
$server = $null
try {
    $statusPath = Join-Path $testPath 'status.json'
    $cancelPath = Join-Path $testPath 'cancelar'
    Initialize-SetupProgress -StatusPath $statusPath -CancelPath $cancelPath
    Write-SetupStatus -Stage 'download' -Message 'Teste' -Percent 14 -CompletedBytes 140 -TotalBytes 1000
    Write-SetupStatus -Stage 'download' -Message 'Atualizado' -Percent 20 -CompletedBytes 200 -TotalBytes 1000
    $snapshot = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
    if ($snapshot.Percent -ne 20 -or $snapshot.CompletedBytes -ne 200) { throw 'A comunicacao entre a janela e o instalador falhou.' }
    [IO.File]::WriteAllText($cancelPath,'cancelar')
    $cancelled = $false
    try { Assert-SetupNotCancelled } catch [OperationCanceledException] { $cancelled=$true }
    if (-not $cancelled) { throw 'Pedido de interrupcao ignorado.' }
    [IO.File]::Delete($cancelPath)
    Write-Host 'OK: atualizacao atomica de status e pedido de interrupcao.'

    $argumentScript=Join-Path $testPath 'argumentos.ps1'
    $argumentResult=Join-Path $testPath 'argumentos.txt'
    [IO.File]::WriteAllText($argumentScript,'param([string]$Value,[string]$OutputPath) [IO.File]::WriteAllText($OutputPath,$Value)')
    foreach ($value in @('C:\','D:\Pasta com espaço\','um"teste')) {
        $arguments=(@('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$argumentScript,'-Value',$value,'-OutputPath',$argumentResult) | ForEach-Object {ConvertTo-NativeArgument $_}) -join ' '
        $child=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
        if ($child.ExitCode -ne 0 -or [IO.File]::ReadAllText($argumentResult) -ne $value) {throw 'Argumentos com barra final, espacos ou aspas foram alterados.'}
        $child.Dispose()
    }
    Write-Host 'OK: caminhos de raiz, espacos, acentos e argumentos com aspas preservados entre processos.'

    if ($Download) {
        Add-Type -Path (Join-Path $PSScriptRoot 'tests\ServidorDownload.cs')
        $server = [Bo2DownloadTestServer]::new()
        New-Item -ItemType Directory -Path $CachePath -Force | Out-Null
        $aria = Get-Aria2 -CachePath $CachePath
        $inputPath = Join-Path $testPath 'entrada.txt'
        $downloadPath = Join-Path $testPath 'arquivos'
        New-Item -ItemType Directory -Path $downloadPath | Out-Null
        $inputLines = @()
        $sha1 = [Security.Cryptography.SHA1]::Create()
        $expected = @{}
        foreach ($name in @('a.bin','b.bin')) {
            $expected[$name]=[BitConverter]::ToString($sha1.ComputeHash($server.Files[$name])).Replace('-','')
            $inputLines += 'http://127.0.0.1:'+$server.Port+'/'+$name
            $inputLines += '  dir='+$downloadPath
            $inputLines += '  out='+$name
            $inputLines += '  checksum=sha-1='+$expected[$name]
        }
        $sha1.Dispose()
        [IO.File]::WriteAllLines($inputPath,[string[]]$inputLines,[Text.UTF8Encoding]::new($false))
        $options=@('--no-conf=true','--continue=false','--allow-overwrite=true','--check-integrity=true','--file-allocation=none','--download-result=hide',('--input-file='+$inputPath))
        $before = @(Get-Process -Name aria2c -ErrorAction SilentlyContinue | ForEach-Object Id)
        [Bo2DownloadTestServer]::CancelAfter($cancelPath,1800)
        $cancelled=$false
        $downloadFailure = ''
        try { $downloadCode = Invoke-AriaDownload -AriaPath $aria -Options ($options+@('--max-overall-download-limit=64K')) -TotalBytes 1310720 -TotalFiles 2; $downloadFailure='Codigo de saida: '+$downloadCode }
        catch { $cancelled = Test-SetupCancellation; $downloadFailure=$_.Exception.Message }
        if (-not $cancelled) { throw ('O download ativo nao foi interrompido. '+$downloadFailure) }
        if (@(Get-ChildItem -LiteralPath $downloadPath -Filter '*.aria2').Count -eq 0) { throw 'A interrupcao nao preservou os controles de retomada.' }
        $orphans = @(Get-Process -Name aria2c -ErrorAction SilentlyContinue | Where-Object {$before -notcontains $_.Id})
        if ($orphans.Count -gt 0) { throw 'Um downloader ficou rodando depois da interrupcao.' }
        [IO.File]::Delete($cancelPath)
        $code = Invoke-AriaDownload -AriaPath $aria -Options $options -TotalBytes 1310720 -TotalFiles 2
        if ($code -ne 0) { throw ('Download por RPC falhou: '+$code) }
        foreach ($name in @('a.bin','b.bin')) {
            if ((Get-FileHash -LiteralPath (Join-Path $downloadPath $name) -Algorithm SHA1).Hash -ne $expected[$name]) { throw ('Arquivo retomado incorreto: '+$name) }
        }
        $snapshot=Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
        if ($snapshot.Percent -ne 100 -or $snapshot.CompletedFiles -ne 2 -or $snapshot.CompletedBytes -ne 1310720) { throw 'O progresso final nao corresponde ao download completo.' }
        $failed=$false
        try {$failed=(Invoke-AriaDownload -AriaPath $aria -Options @('--opcao-de-teste-inexistente=true') -TotalBytes 1 -TotalFiles 1) -ne 0} catch {$failed=$true}
        if (-not $failed) {throw 'Uma falha do downloader foi reportada como sucesso.'}
        Write-Host 'OK: download real via RPC local, interrupcao, encerramento do downloader e retomada com hashes corretos.'
    }

    $requestedPreview = $PreviewPath
    . (Join-Path $packagePath 'Interface.ps1')
    $script:GuiControls.Path.Text='D:\Jogos\BO2-Plutonium'
    Assert-InstallerPackage -Path $packagePath
    $partialPath=Join-Path $testPath 'pacote parcial com espaço'
    New-Item -ItemType Directory -Path $partialPath | Out-Null
    Get-ChildItem -LiteralPath $packagePath -File | Where-Object Name -ne 'instalar.ps1' | Copy-Item -Destination $partialPath
    $completePackagePath=$script:GuiPackagePath
    try {
        $script:GuiPackagePath=$partialPath
        $rejected=$false
        try { Start-InstallerWorker } catch {
            $rejected=$_.Exception.Message -match 'Extrair Tudo' -and $_.Exception.Message -match 'instalar\.ps1'
        }
        if (-not $rejected -or $null -ne $script:GuiWorker -or $script:GuiBusy) {
            throw 'Pacote parcial iniciou um processo ou nao explicou como extrair o ZIP.'
        }
    } finally { $script:GuiPackagePath=$completePackagePath }

    # Uma interface inofensiva permite testar os CMDs sem abrir outra janela.
    [IO.File]::WriteAllText((Join-Path $partialPath 'Interface.ps1'), '[IO.File]::WriteAllText((Join-Path $PSScriptRoot ''iniciado.txt''),''ok'')')
    function Invoke-BatchFixture {
        param([string]$Path)
        $process=[Diagnostics.Process]::new()
        $process.StartInfo.FileName=$env:ComSpec
        $process.StartInfo.Arguments='/d /c ""'+$Path+'""'
        $process.StartInfo.UseShellExecute=$false
        $process.StartInfo.CreateNoWindow=$true
        $process.StartInfo.RedirectStandardInput=$true
        $process.StartInfo.RedirectStandardOutput=$true
        $process.StartInfo.RedirectStandardError=$true
        try {
            [void]$process.Start()
            $process.StandardInput.Close()
            if (-not $process.WaitForExit(15000)) { $process.Kill(); $process.WaitForExit(); throw 'A abertura do CMD nao encerrou no teste.' }
            [pscustomobject]@{Code=$process.ExitCode;Output=$process.StandardOutput.ReadToEnd()+$process.StandardError.ReadToEnd()}
        } finally { $process.Dispose() }
    }
    foreach ($entry in @('INSTALAR.cmd','ALTERNATIVA-TORRENT.cmd')) {
        $result=Invoke-BatchFixture -Path (Join-Path $partialPath $entry)
        if ($result.Code -ne 1 -or $result.Output -notmatch 'Extrair Tudo' -or $result.Output -notmatch 'instalar\.ps1' -or
            [IO.File]::Exists((Join-Path $partialPath 'iniciado.txt'))) {
            throw ('CMD nao bloqueou o pacote parcial: '+$entry+' | '+$result.Output)
        }
    }
    [IO.File]::WriteAllText((Join-Path $partialPath 'instalar.ps1'),'# Fixture: nao instala nem baixa arquivos.')
    foreach ($entry in @('INSTALAR.cmd','ALTERNATIVA-TORRENT.cmd')) {
        $result=Invoke-BatchFixture -Path (Join-Path $partialPath $entry)
        if ($result.Code -ne 0 -or -not [IO.File]::Exists((Join-Path $partialPath 'iniciado.txt'))) {
            throw ('CMD nao abriu um pacote completo: '+$entry+' | '+$result.Output)
        }
        [IO.File]::Delete((Join-Path $partialPath 'iniciado.txt'))
    }
    Write-Host 'OK: pacote sem instalar.ps1 bloqueado na janela e nos dois CMDs; extracao completa permite a abertura.'
    $sample = [pscustomobject]@{State='running';Stage='download';Message='Baixando arquivos do jogo...';Percent=37.5;CompletedBytes=5452767499L;TotalBytes=14540713332L;Speed=12000000L;CompletedFiles=201;TotalFiles=525;Cancellable=$true}
    Set-InstallerSnapshot $sample
    if ($script:GuiControls.Progress.Value -ne 37.5 -or $script:GuiControls.Speed.Text -ne '12,0 MB/s' -or $script:GuiControls.Eta.Text -eq '—') { throw 'A janela nao exibiu os dados reais do status.' }
    $sample.State='cancelled';$sample.Stage='cancelled';$sample.Percent=$null
    Set-InstallerSnapshot $sample
    if ($script:GuiControls.Progress.IsIndeterminate) { throw 'A janela continuou animando apos uma interrupcao.' }
    $sample.State='error';$sample.Stage='error';$sample.Message='Erro de teste'
    Set-InstallerSnapshot $sample
    if ($script:GuiControls.Status.Text -ne 'Erro de teste' -or $script:GuiControls.Progress.IsIndeterminate) {throw 'O erro nao foi apresentado na janela.'}
    $script:GuiOutputPath=Join-Path $testPath 'detalhes.log'
    [IO.File]::WriteAllText($script:GuiOutputPath,'Registro disponivel depois que o processo encerrou.')
    $script:GuiControls.Details.IsExpanded=$true
    Update-InstallerDetails
    if ($script:GuiControls.DetailsBox.Text -notmatch 'Registro disponivel') {throw 'Os detalhes ficaram indisponiveis depois do encerramento do processo.'}
    $script:GuiControls.Details.IsExpanded=$false
    if ($requestedPreview) {
        $script:GuiControls.Path.Text='D:\Jogos\BO2-Plutonium'
        $script:GuiControls.Phase.Text='PRONTO PARA COMEÇAR'
        $script:GuiControls.Status.Text='Tudo pronto para preparar seu jogo.'
        $script:GuiControls.Status.Foreground='#DCE5EF'
        $script:GuiControls.Progress.Value=0
        $script:GuiControls.Percent.Text='0%'
        $script:GuiControls.Speed.Text='—';$script:GuiControls.Eta.Text='—'
        $script:GuiControls.Amount.Text='14,54 GB · 525 arquivos';$script:GuiControls.FileCount.Text=''
        $script:GuiWindow.Add_ContentRendered({Save-InstallerPreview $requestedPreview;$script:GuiWindow.Close()})
        [void]$script:GuiWindow.ShowDialog()
    } else { $script:GuiWindow.Close() }
    Write-Host 'OK: janela WPF, seletor de destino, percentual, velocidade, estimativa e estado interrompido.'
} finally {
    if ($null -ne $server) { $server.Dispose() }
    # Remove somente os arquivos temporarios desta verificacao, sem exclusao recursiva.
    if ([IO.Directory]::Exists($testPath)) {
        Get-ChildItem -LiteralPath $testPath -File -Recurse | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }
        Get-ChildItem -LiteralPath $testPath -Directory -Recurse | Sort-Object {$_.FullName.Length} -Descending | ForEach-Object { Remove-Item -LiteralPath $_.FullName }
        Remove-Item -LiteralPath $testPath
    }
}
