$script:SetupProgress = $null
$script:SetupStatusPath = ''
$script:SetupCancelPath = ''
$script:SetupOwnerProcessId = 0
$script:SetupLastReport = [DateTime]::MinValue

function ConvertTo-NativeArgument {
    param([AllowEmptyString()][string]$Value)
    $escaped = [regex]::Replace($Value,'(\\*)"','$1$1\"')
    return '"'+[regex]::Replace($escaped,'(\\+)$','$1$1')+'"'
}

function Initialize-SetupProgress {
    param([string]$StatusPath, [string]$CancelPath, [int]$OwnerProcessId)
    $script:SetupStatusPath = $StatusPath
    $script:SetupCancelPath = $CancelPath
    $script:SetupOwnerProcessId = $OwnerProcessId
    $script:SetupLastReport = [DateTime]::MinValue
    $script:SetupProgress = [ordered]@{
        State='running'; Stage='preparing'; Message='Preparando a instalacao...'; Percent=$null
        CompletedBytes=0L; TotalBytes=0L; Speed=0L; CompletedFiles=0; TotalFiles=0; Cancellable=$true
    }
}

function Test-SetupCancellation {
    if ($script:SetupCancelPath -and (Test-Path -LiteralPath $script:SetupCancelPath)) { return $true }
    if ($script:SetupOwnerProcessId -gt 0 -and -not (Get-Process -Id $script:SetupOwnerProcessId -ErrorAction SilentlyContinue)) { return $true }
    return $false
}

function Assert-SetupNotCancelled {
    if (Test-SetupCancellation) { throw [OperationCanceledException]::new('Instalacao interrompida. Os arquivos baixados foram preservados.') }
}

function Write-SetupStatus {
    param(
        [string]$Stage, [string]$Message, [string]$State='running', [double]$Percent=-1,
        [long]$CompletedBytes=0, [long]$TotalBytes=0, [long]$Speed=0,
        [int]$CompletedFiles=0, [int]$TotalFiles=0, [bool]$Cancellable=$true, [switch]$Throttle
    )
    if (-not $script:SetupStatusPath) { return }
    if ($Throttle -and ([DateTime]::UtcNow - $script:SetupLastReport).TotalMilliseconds -lt 250) { return }
    $script:SetupLastReport = [DateTime]::UtcNow
    $script:SetupProgress.State = $State
    $script:SetupProgress.Stage = $Stage
    $script:SetupProgress.Message = $Message
    $script:SetupProgress.Percent = if ($Percent -lt 0) { $null } else { [Math]::Min(100,[Math]::Max(0,$Percent)) }
    $script:SetupProgress.CompletedBytes = $CompletedBytes
    $script:SetupProgress.TotalBytes = $TotalBytes
    $script:SetupProgress.Speed = $Speed
    $script:SetupProgress.CompletedFiles = $CompletedFiles
    $script:SetupProgress.TotalFiles = $TotalFiles
    $script:SetupProgress.Cancellable = $Cancellable
    $temporary = $script:SetupStatusPath + '.tmp'
    try {
        [IO.File]::WriteAllText($temporary, ($script:SetupProgress | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
        if ([IO.File]::Exists($script:SetupStatusPath)) { [IO.File]::Replace($temporary, $script:SetupStatusPath, [NullString]::Value) }
        else { [IO.File]::Move($temporary, $script:SetupStatusPath) }
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}

function Measure-DownloadProgress {
    param($Active, $Stopped, [long]$TotalBytes, [int]$TotalFiles, [switch]$TorrentMode)
    $records = @{}
    foreach ($item in $Stopped) { $records[$item.gid] = $item }
    foreach ($item in $Active) { if (-not $records.ContainsKey($item.gid)) { $records[$item.gid] = $item } }
    $bytes = 0L
    $files = 0
    foreach ($item in $records.Values) {
        if ($item.status -eq 'complete' -or $item.status -eq 'active') {
            $bytes += [Math]::Min([long]$item.totalLength, [long]$item.completedLength)
        }
        if ($TorrentMode) {
            if ($item.PSObject.Properties['files']) {
                foreach ($file in $item.files) {
                    if ([long]$file.length -eq [long]$file.completedLength -and [long]$file.length -gt 0) { $files++ }
                }
            }
        } elseif ($item.status -eq 'complete') { $files++ }
    }
    $bytes = [Math]::Min($TotalBytes, $bytes)
    [pscustomobject]@{CompletedBytes=$bytes; CompletedFiles=[Math]::Min($TotalFiles,$files); Percent=$(if ($TotalBytes -gt 0) { 100.0*$bytes/$TotalBytes } else { 0 })}
}

function Invoke-AriaRpc {
    param([int]$Port, [string]$Secret, [switch]$Shutdown)
    if ($Shutdown) {
        $requestBody = @{jsonrpc='2.0'; id='stop'; method='aria2.shutdown'; params=@('token:'+$Secret)}
    } else {
        $keys = @('gid','status','totalLength','completedLength','files')
        $requestBody = @(
            @{jsonrpc='2.0';id='active';method='aria2.tellActive';params=@(('token:'+$Secret),$keys)},
            @{jsonrpc='2.0';id='stopped';method='aria2.tellStopped';params=@(('token:'+$Secret),0,1000,$keys)},
            @{jsonrpc='2.0';id='global';method='aria2.getGlobalStat';params=@('token:'+$Secret)}
        )
    }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($requestBody | ConvertTo-Json -Depth 8 -Compress))
    $request = [Net.HttpWebRequest]::Create('http://127.0.0.1:'+$Port+'/jsonrpc')
    $request.Proxy = $null
    $request.Method = 'POST'
    $request.ContentType = 'application/json'
    $request.Timeout = 2000
    $request.ReadWriteTimeout = 2000
    $request.ContentLength = $bytes.Length
    $stream = $request.GetRequestStream()
    try { $stream.Write($bytes,0,$bytes.Length) } finally { $stream.Dispose() }
    $response = $request.GetResponse()
    try {
        $reader = [IO.StreamReader]::new($response.GetResponseStream())
        try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
        return ($text | ConvertFrom-Json)
    } finally { $response.Dispose() }
}

function Invoke-AriaDownload {
    param([string]$AriaPath, [string[]]$Options, [long]$TotalBytes, [int]$TotalFiles, [switch]$TorrentMode)
    if (-not $script:SetupStatusPath) {
        & $AriaPath @Options | Out-Host
        return [int]$LASTEXITCODE
    }
    Assert-SetupNotCancelled
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
    $listener.Start()
    $port = $listener.LocalEndpoint.Port
    $listener.Stop()
    $secret = [guid]::NewGuid().ToString('N')
    $trackedOptions = $Options + @('--enable-rpc=true','--rpc-listen-all=false','--rpc-allow-origin-all=false',
        ('--rpc-listen-port='+$port),('--rpc-secret='+$secret),'--max-download-result=1000',
        '--auto-save-interval=1',('--stop-with-process='+$PID),'--show-console-readout=false')
    $arguments = ($trackedOptions | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' '
    $logBase = [IO.Path]::Combine([IO.Path]::GetDirectoryName($script:SetupStatusPath),'aria2')
    $process = Start-Process -FilePath $AriaPath -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput ($logBase+'.out.log') -RedirectStandardError ($logBase+'.err.log')
    $null = $process.Handle
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $lastReply = [DateTime]::UtcNow
    $downloadFailed = $false
    try {
        while (-not $process.HasExited) {
            Assert-SetupNotCancelled
            try {
                $responses = Invoke-AriaRpc -Port $port -Secret $secret
                $byId = @{}
                foreach ($reply in $responses) {
                    if ($reply.PSObject.Properties['error']) { throw 'Falha ao consultar o progresso do download.' }
                    $byId[$reply.id] = $reply.result
                }
                $progress = Measure-DownloadProgress -Active $byId['active'] -Stopped $byId['stopped'] -TotalBytes $TotalBytes -TotalFiles $TotalFiles -TorrentMode:$TorrentMode
                $stats = $byId['global']
                Write-SetupStatus -Stage 'download' -Message 'Baixando arquivos do jogo...' -Percent $progress.Percent -CompletedBytes $progress.CompletedBytes -TotalBytes $TotalBytes -Speed ([long]$stats.downloadSpeed) -CompletedFiles $progress.CompletedFiles -TotalFiles $TotalFiles
                $lastReply = [DateTime]::UtcNow
                $expectedTasks = if ($TorrentMode) { 1 } else { $TotalFiles }
                if ([int]$stats.numActive -eq 0 -and [int]$stats.numWaiting -eq 0 -and @($byId['stopped']).Count -ge $expectedTasks) {
                    $downloadFailed = @($byId['stopped'] | Where-Object { $_.status -ne 'complete' }).Count -gt 0
                    [void](Invoke-AriaRpc -Port $port -Secret $secret -Shutdown)
                    if (-not $process.WaitForExit(15000)) { throw 'O downloader nao encerrou apos concluir.' }
                }
            } catch {
                if ($timer.Elapsed.TotalSeconds -gt 15 -and ([DateTime]::UtcNow-$lastReply).TotalSeconds -gt 15) {
                    throw 'O acompanhamento do download parou de responder. Tente novamente para retomar.'
                }
            }
            if (-not $process.HasExited) { Start-Sleep -Milliseconds 500; $process.Refresh() }
        }
        if ($downloadFailed) { return 1 }
        $process.WaitForExit()
        return [int]$process.ExitCode
    } finally {
        if (-not $process.HasExited) {
            try { [void](Invoke-AriaRpc -Port $port -Secret $secret -Shutdown) } catch { }
            if (-not $process.WaitForExit(15000)) { $process.Kill(); $process.WaitForExit() }
        }
        $process.Dispose()
    }
}
