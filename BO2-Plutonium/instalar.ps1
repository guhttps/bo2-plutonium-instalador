[CmdletBinding()]
param(
    [string]$PastaJogos = (Join-Path $env:USERPROFILE 'Games\BO2-Plutonium'),
    [switch]$SomenteBaixar,
    [switch]$SemAbrir,
    [switch]$Torrent,
    [string]$StatusPath,
    [string]$CancelPath,
    [int]$OwnerProcessId=0
)

. (Join-Path $PSScriptRoot 'Funcoes.ps1')
. (Join-Path $PSScriptRoot 'Progresso.ps1')
Initialize-SetupProgress -StatusPath $StatusPath -CancelPath $CancelPath -OwnerProcessId $OwnerProcessId

function Invoke-GameDownload {
    param($Metadata, [string]$CachePath, [string]$Destination, [switch]$UseTorrent)
    Assert-SetupNotCancelled
    Write-SetupStatus -Stage 'preparing' -Message 'Preparando o download...'
    $aria = Get-Aria2 -CachePath $CachePath
    $totalBytes = [long](($Metadata.Files | Measure-Object -Property Length -Sum).Sum)
    $totalFiles = @($Metadata.Files).Count
    $common = @('--no-conf=true', '--check-integrity=true', '--file-allocation=none',
        '--auto-file-renaming=false', '--enable-color=false', '--summary-interval=15',
        '--download-result=hide', '--console-log-level=warn', '--connect-timeout=20', '--timeout=60')
    if ($UseTorrent) {
        Write-Host 'Baixando via BitTorrent. A velocidade depende dos participantes da rede.'
        $options = $common + @('--continue=true', '--seed-time=0', '--bt-stop-timeout=180', '--max-overall-upload-limit=128K',
            ('--dir=' + $Destination), ('--dht-file-path=' + (Join-Path $CachePath 'dht.dat')),
            ('--dht-file-path6=' + (Join-Path $CachePath 'dht6.dat')),
            (Join-Path $PSScriptRoot 'pluto_t6_full_game.torrent'))
        $downloadCode = Invoke-AriaDownload -AriaPath $aria -Options $options -TotalBytes $totalBytes -TotalFiles $totalFiles -TorrentMode
        if ($downloadCode -ne 0) { throw "Torrent interrompido (codigo $downloadCode). Execute novamente para retomar, ou use INSTALAR.cmd para tentar HTTP." }
        return
    }
    $manifestPath = Join-Path $PSScriptRoot 'arquivos-http.json'
    if ((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash -ne 'E7A96F8DC7D7F04B4E19E684001FDD6290CF9F8FE6921788361D82BBA89CCBCF') {
        throw 'O manifesto de download foi alterado ou corrompido. Extraia o ZIP novamente.'
    }
    $files = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $byName = @{}
    foreach ($file in $files) { $byName[$file.name] = $file }
    $bases = @('https://archive.org/download/pluto_t6_full_game_202408/')
    try {
        $location = Invoke-RestMethod -Uri 'https://archive.org/metadata/pluto_t6_full_game_202408' -TimeoutSec 25
        $directBases = @()
        foreach ($server in @($location.d1, $location.d2)) {
            if ($server -match '^[a-z0-9.-]+\.archive\.org$' -and $location.dir -match '^/[0-9]+/items/pluto_t6_full_game_202408$') {
                $directBases += 'https://' + $server + $location.dir + '/'
            }
        }
        $bases = $directBases + $bases
    } catch { Write-Host 'Usando o endereco principal do arquivo HTTP.' }
    $lines = foreach ($entry in $Metadata.Files) {
        $name = $Metadata.Name + '/' + $entry.Path
        if (-not $byName.ContainsKey($name) -or [long]$byName[$name].size -ne $entry.Length -or
            $byName[$name].sha1 -notmatch '^[a-f0-9]{40}$') { throw "Metadados HTTP invalidos: $name" }
        $encoded = ($name.Split('/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
        ($bases | ForEach-Object { $_ + $encoded }) -join "`t"
        '  dir=' + (Join-Path $Destination (Split-Path -Parent $name))
        '  out=' + (Split-Path -Leaf $name)
        '  checksum=sha-1=' + $byName[$name].sha1
    }
    $inputPath = Join-Path $CachePath 'download-http.txt'
    [IO.File]::WriteAllLines($inputPath, [string[]]$lines, (New-Object Text.UTF8Encoding($false)))
    $options = $common + @('--continue=false', '--max-concurrent-downloads=12', '--max-connection-per-server=4', '--split=4',
        '--min-split-size=4M', '--allow-overwrite=true', '--max-tries=5', '--retry-wait=3',
        ('--log=' + (Join-Path $CachePath 'download.log')), '--log-level=notice', ('--input-file=' + $inputPath))
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        Write-Host "Download HTTP, tentativa $attempt/2. Arquivos completos sao reaproveitados."
        Assert-SetupNotCancelled
        $downloadCode = Invoke-AriaDownload -AriaPath $aria -Options $options -TotalBytes $totalBytes -TotalFiles $totalFiles
        if ($downloadCode -eq 0) { return }
    }
    throw 'O download HTTP ficou incompleto. Execute INSTALAR.cmd para retomar. Se a fonte estiver fora do ar, tente ALTERNATIVA-TORRENT.cmd.'
}

function Invoke-FullSetup {
    Assert-SetupNotCancelled
    Write-SetupStatus -Stage 'preparing' -Message 'Preparando a instalacao...'
    if (-not [Environment]::Is64BitOperatingSystem -or [Environment]::OSVersion.Version.Major -lt 10) {
        throw 'Use Windows 10 ou 11 de 64 bits.'
    }
    if (-not $SomenteBaixar -and @(Get-Process -Name 'plutonium-launcher-win32','plutonium-bootstrapper-win32','plutonium' -ErrorAction SilentlyContinue).Count -gt 0) {
        throw 'Feche o Plutonium e o jogo antes de iniciar a instalacao.'
    }
    if ($PastaJogos -match '[\r\n\t]' -or -not [IO.Path]::IsPathRooted($PastaJogos)) { throw 'Pasta de destino invalida.' }
    $destination = [IO.Path]::GetFullPath($PastaJogos)
    $installPath = Join-Path $env:LOCALAPPDATA 'BO2-Plutonium-Assistente'
    $cachePath = Join-Path $installPath 'cache'
    New-Item -ItemType Directory -Path $cachePath -Force | Out-Null
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    $transcribing = $false
    try {
        try {
            Start-Transcript -LiteralPath (Join-Path $installPath ('instalacao-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')) | Out-Null
            $transcribing = $true
        } catch { Write-Warning 'Registro da instalacao indisponivel.' }
        Write-Host 'BLACK OPS 2 / PLUTONIUM - MULTIPLAYER E ZOMBIES' -ForegroundColor Cyan
        Write-Host ('Destino: ' + $destination)
        Write-Host 'Download do jogo: 14,54 GB. E possivel fechar e executar novamente para retomar.'
        $torrentPath = Join-Path $PSScriptRoot 'pluto_t6_full_game.torrent'
        if ((Get-FileHash -LiteralPath $torrentPath -Algorithm SHA256).Hash -ne '96A4BEECEF0CC0BA8CDD0D59F54ECC7721E837A44A9ECD78AE5834D18D2A2D89') {
            throw 'O torrent original foi alterado ou corrompido.'
        }
        if (-not ('Bo2Torrent' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'TorrentVerifier.cs') }
        $metadata = [Bo2Torrent]::Load($torrentPath)
        if ($metadata.InfoHash -ne '228d582decc9415565f1413cd1b755cad3d8a490') { throw 'Infohash inesperado.' }
        Write-Host '[1/5] Verificando arquivos existentes...'
        Write-SetupStatus -Stage 'verifying' -Message 'Conferindo arquivos existentes...' -Percent 0
        $verifyProgress = [Action[long,long]]{
            param($done, $total)
            Assert-SetupNotCancelled
            Write-Progress -Activity 'Verificando integridade do BO2' -PercentComplete ([int](100*$done/$total))
            Write-SetupStatus -Stage 'verifying' -Message 'Verificando a integridade dos arquivos...' -Percent (100.0*$done/$total) -CompletedBytes $done -TotalBytes $total -Throttle
        }
        $valid = $false
        try { $metadata.Verify($destination, $verifyProgress); $valid = $true }
        catch { Assert-SetupNotCancelled; Write-Host 'Ha arquivos para baixar ou reparar.' }
        if (-not $valid) {
            $driveRoot = [IO.Path]::GetPathRoot($destination)
            $drive = New-Object IO.DriveInfo($driveRoot)
            if ($drive.AvailableFreeSpace -lt 16GB) { throw 'Deixe pelo menos 16 GB livres no disco do jogo antes de baixar ou reparar.' }
            Invoke-GameDownload -Metadata $metadata -CachePath $cachePath -Destination $destination -UseTorrent:$Torrent
        }
        Write-Host '[2/5] Conferindo todos os blocos com o torrent original...'
        Assert-SetupNotCancelled
        if (-not $valid) {
            Write-SetupStatus -Stage 'verifying' -Message 'Conferindo o download completo...' -Percent 0
            $metadata.Verify($destination, $verifyProgress)
        }
        Write-Progress -Activity 'Verificando integridade do BO2' -Completed
        $gamePath = Join-Path $destination $metadata.Name
        Write-Host 'Integridade: 55.469 blocos conferidos.' -ForegroundColor Green
        if ($SomenteBaixar) { Write-Host ('Download concluido: ' + $gamePath); return }

        Write-Host '[3/5] Preparando componentes Microsoft...'
        Assert-SetupNotCancelled
        Write-SetupStatus -Stage 'components' -Message 'Preparando componentes Microsoft. Confirme a janela do Windows se for solicitado.' -Cancellable $false
        & (Join-Path $PSScriptRoot 'componentes.ps1') -GamePath $gamePath -CachePath $cachePath
        if ($LASTEXITCODE -ne 0) { throw 'A instalacao dos componentes ficou pendente. Execute novamente.' }
        Assert-SetupNotCancelled

        Write-Host '[4/5] Instalando/atualizando o cliente oficial do Plutonium...'
        Write-SetupStatus -Stage 'client' -Message 'Instalando e atualizando o Plutonium...' -Cancellable $false
        $launcherPath = Join-Path $installPath 'plutonium.exe'
        if (@(Get-Process -Name 'plutonium-launcher-win32', 'plutonium-bootstrapper-win32', 'plutonium' -ErrorAction SilentlyContinue).Count -gt 0) {
            throw 'Feche o Plutonium e o jogo e execute o instalador novamente. Os downloads serao reaproveitados.'
        }
        Get-OfficialLauncher -Destination $launcherPath
        $clientPath = Join-Path $env:LOCALAPPDATA 'Plutonium'
        $updater = Start-Process -FilePath $launcherPath -ArgumentList '-update-only' -PassThru
        Wait-PlutoniumUpdate -Process $updater
        Assert-SetupNotCancelled
        foreach ($relative in @('bin\plutonium-launcher-win32.exe', 'bin\plutonium-bootstrapper-win32.exe')) {
            if (-not (Test-Executable -Path (Join-Path $clientPath $relative))) { throw "Arquivo do cliente ausente: $relative" }
        }
        Write-Host '[5/5] Configurando o jogo e criando atalho...'
        Write-SetupStatus -Stage 'configuring' -Message 'Configurando a pasta do jogo e criando o atalho...' -Cancellable $false
        Set-GamePath -ConfigPath (Join-Path $clientPath 'config.json') -GamePath $gamePath
        $desktop = [Environment]::GetFolderPath('Desktop')
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut((Join-Path $desktop 'Plutonium - BO2.lnk'))
        $shortcut.TargetPath = $launcherPath
        $shortcut.WorkingDirectory = $installPath
        $shortcut.Description = 'Black Ops 2 Multiplayer e Zombies pelo Plutonium'
        $shortcut.Save()
        Write-Host ''
        Write-Host 'Arquivos instalados e verificados. Entre com sua conta no Plutonium e escolha PLAY.' -ForegroundColor Green
        Write-Host 'Cadastro: https://forum.plutonium.pw/register'
        Write-Host ('Pasta do jogo: ' + $gamePath)
        if (-not $SemAbrir) { Start-Process -FilePath $launcherPath -WorkingDirectory $installPath | Out-Null }
    } finally {
        if ($transcribing) { Stop-Transcript | Out-Null }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    $setupMutex = [Threading.Mutex]::new($false,('Local\BO2-Plutonium-Install-'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
    $ownsMutex = $false
    try {
        try { $ownsMutex = $setupMutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsMutex = $true }
        if (-not $ownsMutex) { throw 'Ja existe outra instalacao em andamento. Aguarde sua conclusao.' }
        Invoke-FullSetup
        $message = if ($SomenteBaixar) { 'Download concluido e arquivos verificados.' } else { 'Instalacao concluida! Entre na sua conta no Plutonium e escolha PLAY.' }
        Write-SetupStatus -Stage 'complete' -State 'complete' -Message $message -Percent 100 -Cancellable $false
    }
    catch {
        Write-Progress -Activity 'Verificando integridade do BO2' -Completed
        if (Test-SetupCancellation) {
            Write-SetupStatus -Stage 'cancelled' -State 'cancelled' -Message 'Instalacao interrompida. Continue depois usando a mesma pasta.' -Cancellable $false
            exit 2
        }
        Write-SetupStatus -Stage 'error' -State 'error' -Message $_.Exception.Message -Cancellable $false
        Write-Host ('Instalacao incompleta: ' + $_.Exception.Message) -ForegroundColor Red
        Write-Host 'Os arquivos baixados ficam salvos para a proxima tentativa.'
        exit 1
    }
    finally {
        if ($ownsMutex) { $setupMutex.ReleaseMutex() }
        $setupMutex.Dispose()
    }
}
